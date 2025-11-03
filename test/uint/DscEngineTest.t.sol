// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployEngineScript} from "../../script/Engine.s.sol";
import {HelperConfig} from "../../script/helperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {StableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/MockERC20.sol";

contract TestEngine is Test {
    DeployEngineScript deployer;
    DSCEngine engine;
    StableCoin coin;
    address ethpricefeed;
    address btcpricefeed;
    address eth;
    address btc;
    address user = makeAddr("vishal");

    function setUp() public {
        deployer = new DeployEngineScript();
        HelperConfig helper;
        (engine, coin, helper) = deployer.run();
        (ethpricefeed, btcpricefeed, eth, btc,) = helper.activeNetworkConfig();

        ERC20Mock(eth).mint(user, 100 ether);
        ERC20Mock(btc).mint(user, 100 ether);
    }

    // modifier

    modifier _depositCollateral() {
        vm.startPrank(user);
        ERC20Mock(eth).approve(address(engine), 10 ether);
        engine.depositCollateral(eth, 10 ether);
        vm.stopPrank();
        _;
    }

    ///////////////////////
    // Constructor Tests //
    ///////////////////////
    address[] public tokenAddress;
    address[] public priceFeed;

    function testConstructorRevert() public {
        tokenAddress.push(eth);
        tokenAddress.push(btc);
        priceFeed.push(ethpricefeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddress, priceFeed, address(coin));
    }

    //////////////////
    // User Tests //
    //////////////////

    function testBalanceOfUser() public view {
        uint256 expectedBalance = 100 ether;
        uint256 balance = ERC20Mock(eth).balanceOf(user);
        assertEq(expectedBalance, balance);
    }

    //////////////////
    // Price Tests //
    //////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15 ether;
        uint256 price = engine.getUsdValue(eth, ethAmount);
        uint256 expected = 30000e18;
        assertEq(expected, price);
    }

    function testgetTokenAmountFromUsd() public {
        uint256 expectedeth = 0.005 ether;
        uint256 tokens = engine.getTokenAmountFromUsd(eth, 10 ether);
        assertEq(expectedeth, tokens);
    }

    ///////////////////
    // Deposit Tests //
    ///////////////////

    function testmoreThanZero() public {
        vm.startPrank(user);
        ERC20Mock(eth).approve(address(engine), 10 ether);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.depositCollateral(eth, 0 ether);
        vm.stopPrank();
    }

    function testisAllowedToken() public {
        ERC20Mock mock = new ERC20Mock("wsol", "sol", msg.sender, 1000e8);
        vm.startPrank(user);
        ERC20Mock(mock).approve(address(mock), 10 ether);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.depositCollateral(address(mock), 10 ether);
        vm.stopPrank();
    }

    function testdepositCollateral() public _depositCollateral {
        (uint256 totalDscMinted, uint256 collatearlValueInUsd) = engine.getAccountInformation(user);
        assertEq(totalDscMinted, 0);
        uint256 collateralValue = engine.getTokenAmountFromUsd(eth, collatearlValueInUsd);
        assertEq(collateralValue, 10 ether);
    }

    /////////////////////////////
    // Deposit & Minting Tests //
    /////////////////////////////

    function testMintMorethenDeposit() public {
        vm.startPrank(user);
        uint256 ethervalue = engine.getTokenAmountFromUsd(eth, 10 ether);
        ERC20Mock(eth).approve(address(engine), ethervalue);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                0 // The actual health factor value being reverted with
            )
        );
        engine.depositCollateralAndMintDsc(eth, ethervalue, 20 ether);
        vm.stopPrank();
    }

    function testdepositCollateralAndMintDsc() public {
        vm.startPrank(user);
        ERC20Mock(eth).approve(address(engine), 10 ether);
        engine.depositCollateralAndMintDsc(eth, 10 ether, 5 ether);
        (uint256 totalDscMinted, uint256 collatearlValueInUsd) = engine.getAccountInformation(user);
        assertEq(totalDscMinted, 5 ether);
        uint256 collateralValue = engine.getTokenAmountFromUsd(eth, collatearlValueInUsd);
        assertEq(collateralValue, 10 ether);
        vm.stopPrank();
    }

    ///////////////////
    // Minting Tests //
    ///////////////////

    function testMintMoreDSC() public _depositCollateral {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__BreaksHealthFactor.selector,
                0 // The actual health factor value being reverted with
            )
        );
        engine.mintDsc(10001 ether);
        vm.stopPrank();
    }

    function testMintEqualDSC() public _depositCollateral {
        vm.startPrank(user);
        uint256 expectedtoken = 10000 ether;
        engine.mintDsc(expectedtoken);

        uint256 balance = coin.balanceOf(user);

        assertEq(expectedtoken, balance);

        vm.stopPrank();
    }

    function testMintZeroDSC() public _depositCollateral {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testMintDSC() public _depositCollateral {
        vm.startPrank(user);
        uint256 expectedtoken = 4 ether;
        engine.mintDsc(expectedtoken);

        uint256 balance = coin.balanceOf(user);

        assertEq(expectedtoken, balance);

        vm.stopPrank();
    }

    ///////////////////
    // Redeem Tests ///
    ///////////////////

    function testredeemCollateralForDsc() public _depositCollateral {
        vm.startPrank(user);
        engine.mintDsc(5000 ether);
        ERC20Mock(address(coin)).approve(address(engine), 5000 ether);
        engine.redeemCollateralForDsc(eth, 10 ether, 5000 ether);
        vm.stopPrank();
    }

    function testRedeemAfterMintAndRedeemMore() public _depositCollateral {
        vm.startPrank(user);
        engine.mintDsc(5000 ether);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        engine.redeemCollateral(eth, 7 ether);
        vm.stopPrank();
    }

    function testRedeemAfterMint() public _depositCollateral {
        vm.startPrank(user);

        uint256 collatearlValueInUsdbefore = engine.getAccountCollateralValue(user);
        assertEq(collatearlValueInUsdbefore, 20000 ether);
        engine.mintDsc(5000 ether);
        engine.redeemCollateral(eth, 2.5 ether);
        uint256 collatearlValueInUsd = engine.getAccountCollateralValue(user);
        assertEq(collatearlValueInUsd, 15000 ether);
        vm.stopPrank();
    }

    function testRedeemInvalidToken() public _depositCollateral {
        vm.startPrank(user);
        ERC20Mock mock = new ERC20Mock("mock", "moc", msg.sender, 1000e8);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        engine.redeemCollateral(address(mock), 10 ether);
        vm.stopPrank();
    }

    function testRedeemZero() public _depositCollateral {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.redeemCollateral(eth, 0);
        vm.stopPrank();
    }

    function testredeemCollateralWithoutMinting() public _depositCollateral {
        vm.startPrank(user);
        uint256 collatearlValueInUsdbefore = engine.getAccountCollateralValue(user);
        assertEq(collatearlValueInUsdbefore, 20000 ether);
        engine.redeemCollateral(eth, 10 ether);
        uint256 collatearlValueInUsd = engine.getAccountCollateralValue(user);
        assertEq(collatearlValueInUsd, 0);
        vm.stopPrank();
    }

    ///////////////////
    //   Burn Tests ///
    ///////////////////

    function testburnDsc() public _depositCollateral {
        vm.startPrank(user);

        engine.mintDsc(5000 ether);
        uint256 balance = coin.balanceOf(user);
        assertEq(balance, 5000 ether);
        coin.approve(address(engine), 5000 ether);
        engine.burnDsc(5000 ether);
        uint256 balanceAfterBurn = coin.balanceOf(user);
        assertEq(balanceAfterBurn, 0);
        vm.stopPrank();
    }

    function testburnMoreDSCThenMinted() public _depositCollateral {
        vm.startPrank(user);

        engine.mintDsc(50);
        uint256 balance = coin.balanceOf(user);
        assertEq(balance, 50);
        coin.approve(address(engine), 50);
        vm.expectRevert();
        engine.burnDsc(51);
        vm.stopPrank();
    }

    function testBurnZerodsc() public _depositCollateral {
        vm.startPrank(user);

        engine.mintDsc(50);
        uint256 balance = coin.balanceOf(user);
        assertEq(balance, 50);
        coin.approve(address(engine), 50);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }

    ///////////////////////////////////////////////
    // Constant Getter Tests
    ///////////////////////////////////////////////

    function testGetPrecision() public view {
        uint256 precision = engine.getPrecision();
        assertEq(precision, 1e18, "Precision should be 1e18");
    }

    function testGetAdditionalFeedPrecision() public view {
        uint256 additionalPrecision = engine.getAdditionalFeedPrecision();
        assertEq(additionalPrecision, 1e10, "Additional feed precision should be 1e10");
    }

    function testGetLiquidationThreshold() public view {
        uint256 threshold = engine.getLiquidationThreshold();
        assertEq(threshold, 50, "Liquidation threshold should be 50%");
    }

    function testGetLiquidationBonus() public view {
        uint256 bonus = engine.getLiquidationBonus();
        assertEq(bonus, 10, "Liquidation bonus should be 10%");
    }

    function testGetLiquidationPrecision() public view {
        uint256 precision = engine.getLiquidationPrecision();
        assertEq(precision, 100, "Liquidation precision should be 100");
    }

    function testGetMinHealthFactor() public view {
        uint256 minHealthFactor = engine.getMinHealthFactor();
        assertEq(minHealthFactor, 1, "Minimum health factor should be 1");
    }

    function testGetCollateralTokens() public view {
        address[] memory collateralTokens = engine.getCollateralTokens();
        assertEq(collateralTokens.length, 2, "Should have 2 collateral tokens");
        assertEq(collateralTokens[0], eth, "First token should be ETH");
        assertEq(collateralTokens[1], btc, "Second token should be BTC");
    }

    function testGetDsc() public view {
        address dscAddress = engine.getDsc();
        assertEq(dscAddress, address(coin), "DSC address should match deployed contract");
    }

    function testGetCollateralTokenPriceFeed() public view {
        address ethPriceFeed = engine.getCollateralTokenPriceFeed(eth);
        address btcPriceFeed = engine.getCollateralTokenPriceFeed(btc);

        assertEq(ethPriceFeed, ethpricefeed, "ETH price feed should match");
        assertEq(btcPriceFeed, btcpricefeed, "BTC price feed should match");
    }

    function testGetCollateralTokenPriceFeedReturnsZeroForInvalidToken() public  {
        address invalidToken = makeAddr("invalidToken");
        address testpriceFeed = engine.getCollateralTokenPriceFeed(invalidToken);
        assertEq(testpriceFeed, address(0), "Invalid token should return zero address");
    }

    ///////////////////////////////////////////////
    // Constants Relationship Tests
    ///////////////////////////////////////////////

    function testLiquidationThresholdAndPrecisionRelationship() public view {
        uint256 threshold = engine.getLiquidationThreshold();
        uint256 precision = engine.getLiquidationPrecision();

        // Threshold should always be less than precision (50 < 100)
        assertTrue(threshold < precision, "Threshold must be less than precision");

        // This means max 50% collateralization
        uint256 maxCollateralizationRatio = (threshold * 100) / precision;
        assertEq(maxCollateralizationRatio, 50, "Max collateralization should be 50%");
    }

    function testLiquidationBonusIsReasonable() public view {
        uint256 bonus = engine.getLiquidationBonus();

        // Bonus should be between 0 and 100 (0% to 100%)
        assertTrue(bonus > 0, "Bonus should be greater than 0");
        assertTrue(bonus < 100, "Bonus should be less than 100%");
    }

    function testPrecisionValuesAreConsistent() public view {
        uint256 precision = engine.getPrecision();
        uint256 additionalPrecision = engine.getAdditionalFeedPrecision();

        // Standard precision is 18 decimals (1e18)
        assertEq(precision, 1e18, "Standard precision should be 1e18");

        // Additional precision for Chainlink feeds (8 decimals to 18 decimals = 1e10)
        assertEq(additionalPrecision, 1e10, "Additional precision should be 1e10");

        // Together they should create 1e18 from 1e8
        assertEq(precision, additionalPrecision * 1e8, "Precisions should multiply correctly");
    }

    ///////////////////////////////////////////////
    // Deployment Verification Tests
    ///////////////////////////////////////////////

    function testEngineIsDeployedCorrectly() public view {
        assertTrue(address(engine) != address(0), "Engine should be deployed");
        assertTrue(address(coin) != address(0), "Coin should be deployed");
    }

    function testPriceFeedsAreSet() public view {
        assertTrue(ethpricefeed != address(0), "ETH price feed should be set");
        assertTrue(btcpricefeed != address(0), "BTC price feed should be set");
    }

    function testCollateralTokensAreSet() public view {
        assertTrue(eth != address(0), "ETH token should be set");
        assertTrue(btc != address(0), "BTC token should be set");
    }

    function testUserHasInitialBalance() public view {
        uint256 ethBalance = ERC20Mock(eth).balanceOf(user);
        uint256 btcBalance = ERC20Mock(btc).balanceOf(user);

        assertEq(ethBalance, 100 ether, "User should have 100 ETH");
        assertEq(btcBalance, 100 ether, "User should have 100 BTC");
    }
}

