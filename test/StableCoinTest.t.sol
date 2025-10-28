// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StableCoin} from "../src/DecentralizedStableCoin.sol";
import {console} from "forge-std/console.sol";

contract TestStableCoin is Test {
    StableCoin private stableCoin;

    address private admin = makeAddr("Admin");
    address private user = makeAddr("Vishal");

    function setUp() public {
        vm.prank(admin);
        stableCoin = new StableCoin();
    }

    function testMint() public {
        vm.prank(admin);
        stableCoin.mint(user, 100 ether);
        assertEq(stableCoin.balanceOf(user), 100 ether);
    }

    function testMintwithZero() public {
        vm.prank(admin);
        vm.expectRevert();
        stableCoin.mint(user, 0 ether);
    }

    function testMintToZero() public {
        address zero = address(0);
        console.log(zero);
        vm.prank(admin);
        vm.expectRevert();
        stableCoin.mint(zero, 100 ether);
    }
}
