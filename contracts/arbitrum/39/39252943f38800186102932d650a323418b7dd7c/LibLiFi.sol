// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
/******************************************************************************/
import { IDiamondCut } from "./IDiamondCut.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./console.sol";
// Remember to add the loupe functions from DiamondLoupeFacet to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard

error LiFiError(bytes _data);
error UnknownLiFiError();

library LibLiFi {
    using SafeERC20 for IERC20;

    bytes32 constant LIFI_STORAGE_POSITION = keccak256("lifi.portal.strateg.io");

    event LiFiExecutionResult(bool success, bytes returnData);

    struct LiFiConfig {
        address diamond;
    }

    struct LiFiStorage {
        LiFiConfig config;
        
    }

    function lifiStorage() internal pure returns (LiFiStorage storage ds) {
        bytes32 position = LIFI_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function setDiamond(address _diamond) internal {
        LiFiStorage storage store = lifiStorage();
        store.config.diamond = _diamond;
    }

    function getDiamond() internal view returns (address) {
        return lifiStorage().config.diamond;
    }

    function execute(address _sourceAsset, address _approvalAddress, uint256 _amount, bytes calldata _data) internal {
        LiFiStorage storage store = lifiStorage();
        address lifiDiamond = store.config.diamond;
        IERC20(_sourceAsset).safeApprove(_approvalAddress, _amount);
        
        (bool success, bytes memory returnData) = lifiDiamond.call{value: msg.value}(_data);
        if (!success) {
            if (returnData.length == 0) revert UnknownLiFiError();
            assembly {
                revert(add(32, returnData), mload(returnData))
            }
        }

        IERC20(_sourceAsset).safeApprove(lifiDiamond, 0);
        emit LiFiExecutionResult(success, returnData);
    }

}

