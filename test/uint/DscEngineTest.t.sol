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

    function testRedeemAfterMintAndRedeemMore() public _depositCollateral {
        vm.startPrank(user);
        engine.mintDsc(5000 ether);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector,0)
        );
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
        ERC20Mock mock = new ERC20Mock("mock","moc",msg.sender,1000e8);
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
}
