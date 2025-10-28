// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {StableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

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
    
    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__TokenAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amount) private s_DscMinted;

    address[] private s_collateralToken;

    StableCoin private immutable i_stablecoin;


    event CollateralDeposited(address indexed sender,address indexed tokenaddress,uint256 indexed amount);

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    constructor(
        address[] memory tokenAddress,
        address[] memory priceFeedAddress,
        address stablecoinaddress
    ) {
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralToken.push(tokenAddress[i]);
        }
        i_stablecoin = StableCoin(stablecoinaddress);
    }

    function depositCollateralAndMintDsc() external {}

    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] = amountCollateral;
        emit CollateralDeposited(msg.sender,tokenCollateralAddress,amountCollateral);
        bool success= IERC20(tokenCollateralAddress).transferFrom(msg.sender,address(this),amountCollateral);
        if(!success){
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function MintDsc(uint256 amountDSCToMint) external moreThanZero(amountDSCToMint) nonReentrant{
        s_DscMinted[msg.sender] += amountDSCToMint;
        
        revertifHelthFactorIsBroken(msg.sender);
    }

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external {}

    function getAccountCollateralValue(address user) public view returns(uint256) {
        for(uint256 i=0;i<s_collateralToken.length;i++){
            address token = s_collateralToken[i];
            uint256 amount = s_collateralDeposited[user][token];

        }
    }

    function _getAccountInformation(address user) private view returns(uint256 totalDSCMinted,uint256 collatearlValueInUsd){
        totalDSCMinted = s_DscMinted[user];
        collatearlValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns(uint256){
        (uint256 totalDSCMinted, uint256 collatearlValueInUsd) = _getAccountInformation(user);
    }

    function _revertifHelthFactorIsBroken(address user) internal view {

    }

    function getUsdValue(address token,uint256 amount) public view returns(uint256){

    }
}
