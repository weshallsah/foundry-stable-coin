// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {StableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/console.sol";

/**
 * @title DSCEngine
 * @author vishal sah
 *
 * the system is desgine to be as minimal as possible, and have the tokens maintian a 1$ == 1token peg.
 * this stablecoin has the properties:
 * -Exogenous Collateral
 * -Doller Pegged
 * -Algorithmically stable
 *
 * it's similar to DAI had no governance, on fees and was only backed by WETH and WBTC.
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 *
 * @notice This contract is very lossely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    //
    // Errors
    //
    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__TokenAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userhealthFactor);
    error DSCEngine__InvalidPrice();
    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__HealthIsOK();

    //
    // State Variable
    //
    mapping(address token => address priceFeed) private s_PriceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_CollateralDeposited;
    mapping(address user => uint256 amount) private s_DscMinted;

    address[] private s_CollateralToken;

    StableCoin private immutable i_Stablecoin;

    uint256 constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 constant PRECISION = 1e18;
    uint256 constant LIQUIDATION_THRESHOLD = 50;
    uint256 constant LIQUIDATION_PRECISION = 100;
    uint256 constant MIN_HEALTH_FACTOR = 1;
    uint256 constant LIQUIDATION_BONUS = 10;

    //
    // Event
    //
    event CollateralDeposited(address indexed sender, address indexed tokenaddress, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 collateralAmount);

    //
    // Modifier
    //
    modifier moreThanZero(uint256 amount) {
        _moreThanZero(amount);
        _;
    }

    modifier isAllowedToken(address token) {
        _isAllowedToken(token);
        _;
    }

    //
    // Functions
    //
    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address stablecoinaddress) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_PriceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_CollateralToken.push(tokenAddress[i]);
        }
        i_Stablecoin = StableCoin(stablecoinaddress);
    }

    //
    // external
    //
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function redeemCollateralForDsc(address token, uint256 collateralAmount, uint256 amountDscToBurn)
        external
        moreThanZero(collateralAmount)
        isAllowedToken(token)
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(token, collateralAmount, msg.sender, msg.sender);
        _revertifHelthFactorIsBroken(msg.sender);
    }

    function redeemCollateral(address token, uint256 collateralAmount)
        external
        moreThanZero(collateralAmount)
        nonReentrant
        isAllowedToken(token)
    {
        _redeemCollateral(token, collateralAmount, msg.sender, msg.sender);
        _revertifHelthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 amountDscToBurn) external moreThanZero(amountDscToBurn) nonReentrant {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _revertifHelthFactorIsBroken(msg.sender);
    }

    function liquidate(address collateral, address user, uint256 debtTocover)
        external
        nonReentrant
        isAllowedToken(collateral)
        moreThanZero(debtTocover)
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthIsOK();
        }

        uint256 tokenAmountTodethCover = getTokenAmountFromUsd(collateral, debtTocover);
        uint256 liquidateBonus = (tokenAmountTodethCover * LIQUIDATION_BONUS) / 100;

        _redeemCollateral(collateral, tokenAmountTodethCover + liquidateBonus, user, msg.sender);
        _burnDsc(debtTocover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        // This conditional should never hit, but just in case
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertifHelthFactorIsBroken(msg.sender);
    }

    //
    // public
    //

    function getTokenAmountFromUsd(address token, uint256 deth) public view returns (uint256) {
        AggregatorV3Interface pricefeed = AggregatorV3Interface(s_PriceFeeds[token]);
        (, int256 price,,,) = pricefeed.latestRoundData();
        return (deth * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;

        _revertifHelthFactorIsBroken(msg.sender);

        bool minted = i_Stablecoin.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_CollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_CollateralToken.length; i++) {
            address token = s_CollateralToken[i];
            uint256 amount = s_CollateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface pricefeed = AggregatorV3Interface(s_PriceFeeds[token]);
        (, int256 price,,,) = pricefeed.latestRoundData();

        if (price <= 0) {
            revert DSCEngine__InvalidPrice();
        }

        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
    }

    //
    // internal view & pure
    //
    function _revertifHelthFactorIsBroken(address user) internal view {
        uint256 userhealthFactor = _healthFactor(user);
        if (userhealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userhealthFactor);
        }
    }

    function _isAllowedToken(address token) internal view {
        if (s_PriceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
    }

    function _moreThanZero(uint256 amount) internal pure {
        if (amount == 0) {
            revert DSCEngine__NeedMoreThanZero();
        }
    }

    //
    // private
    //
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collatearlValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collatearlValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collatearlValueInUsd) = _getAccountInformation(user);
        // console.log(totalDscMinted);
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (collatearlValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        // console.log((collateralAdjustedForThreshold ));
        return (collateralAdjustedForThreshold) / totalDscMinted;
    }

    function _redeemCollateral(address token, uint256 collateralAmount, address from, address to) private {
        s_CollateralDeposited[from][token] -= collateralAmount;
        emit CollateralRedeemed(from, to, token, collateralAmount);
        bool success = IERC20(token).transfer(to, collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(uint256 coinAmount, address onBehafOf, address from) private {
        s_DscMinted[onBehafOf] -= coinAmount;
        bool success = i_Stablecoin.transferFrom(from, address(this), coinAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_Stablecoin.burn(coinAmount);
    }

    //
    // external pure & view functions
    //

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAccountInformation(address user)
        external
        returns (uint256 totalDscMinted, uint256 collatearlValueInUsd)
    {
        (totalDscMinted, collatearlValueInUsd) = _getAccountInformation(user);
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_CollateralToken;
    }

    function getDsc() external view returns (address) {
        return address(i_Stablecoin);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_PriceFeeds[token];
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
