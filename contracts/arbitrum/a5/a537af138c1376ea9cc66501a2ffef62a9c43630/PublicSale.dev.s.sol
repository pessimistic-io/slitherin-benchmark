// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./Script.sol";
import "./ERC20.sol";

import "./PublicSale.sol";
import {Address} from "./Addresses.sol";

contract MockStable is ERC20 {
    constructor() ERC20("Mock USD", "MUSD") {
        _mint(msg.sender, 1 * 1e6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function claim() public {
        _mint(msg.sender, 10_000 * 1e6);
    }
}

contract PublishScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // address arb1_usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
        // address pearFireblocks = 0xeDF7a5BC543874b81DEeCa16BCbF8FA43E03BD7a;
        MockStable musd = new MockStable();
        console.log(address(musd));
        address admin = 0x0C9cCbaDa1411687f6FFa7df317Af35B16b1FE0C;
        // deploy PublicSale contract
        PublicSale publicSale = new PublicSale(address(musd), admin);
        console.log(address(publicSale));

        vm.stopBroadcast();
    }
}

