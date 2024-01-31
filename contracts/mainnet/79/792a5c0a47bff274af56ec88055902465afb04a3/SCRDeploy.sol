/*
```_____````````````_````_`````````````````_``````````````_````````````
``/`____|``````````|`|``|`|```````````````|`|````````````|`|```````````
`|`|`````___```___`|`|`_|`|__```___```___`|`|`__```````__|`|`_____```__
`|`|````/`_`\`/`_`\|`|/`/`'_`\`/`_`\`/`_`\|`|/`/``````/`_``|/`_`\`\`/`/
`|`|___|`(_)`|`(_)`|```<|`|_)`|`(_)`|`(_)`|```<```_``|`(_|`|``__/\`V`/`
``\_____\___/`\___/|_|\_\_.__/`\___/`\___/|_|\_\`(_)``\__,_|\___|`\_/``
```````````````````````````````````````````````````````````````````````
```````````````````````````````````````````````````````````````````````
*/

// -> Cookbook is a free smart contract marketplace. Find, deploy and contribute audited smart contracts.
// -> Follow Cookbook on Twitter: https://twitter.com/cookbook_dev
// -> Join Cookbook on Discord:https://discord.gg/WzsfPcfHrk

// -> Find this contract on Cookbook: https://www.cookbook.dev/contracts/scr-deploy-using-create/?utm=code



// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "./Ownable.sol";

/**
 * @title SCR Deploy using create
 * @author Breakthrough Labs Inc.
 * @notice Utility
 * @custom:version Experimental.1
 * @custom:address 1
 * @custom:default-precision 0
 * @custom:simple-description Smart Contract Recipes Deployer
 * @dev Smart Contract Recipes Deployer
 *
 */
contract SCRDeploy is Ownable {
    event Deploy(address indexed deployer, address indexed deployment);

    function deployContract(bytes memory bytecode)
        external
        payable
        returns (address)
    {
        address deployedAddress;
        require(bytecode.length != 0, "Create: bytecode length is zero");
        assembly {
            deployedAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(deployedAddress != address(0), "Create: Failed on deploy");
        emit Deploy(msg.sender, deployedAddress);
        return deployedAddress;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }
}

