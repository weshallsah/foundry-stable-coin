// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {StableCoin} from "../src/DecentralizedStableCoin.sol";
import {Script} from "forge-std/Script.sol";

contract DeployStableCoinScript is Script {
    function run(address admin) public returns (StableCoin) {
        vm.startBroadcast(admin);
        StableCoin stablecoin = new StableCoin();
        vm.stopBroadcast();
        return stablecoin;
    }
}
