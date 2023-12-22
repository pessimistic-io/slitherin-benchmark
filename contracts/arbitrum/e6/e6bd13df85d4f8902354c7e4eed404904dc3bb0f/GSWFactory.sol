// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {Address} from "./Address.sol";
import {Clones} from "./Clones.sol";

import {GaslessSmartWallet} from "./GaslessSmartWallet.sol";
import {IGaslessSmartWallet} from "./IGaslessSmartWallet.sol";
import {IGSWFactory} from "./IGSWFactory.sol";

error GSWFactory__NotEOA();

/// @title  GSWFactory
/// @notice Deploys GaslessSmartWallet clones (EIP-1167 minimal proxy) at deterministic addresses using Create2
contract GSWFactory is IGSWFactory {
    using Clones for address;
    address public immutable gswImpl;

    /// @notice Emitted when a new GaslessSmartWallet has been deployed
    event GSWDeployed(address indexed owner, address indexed gsw);

    modifier onlyEOA(address owner) {
        if (Address.isContract(owner)) {
            revert GSWFactory__NotEOA();
        }
        _;
    }

    constructor() {
        // Create GaslessSmartWallet logic contract
        gswImpl = address(new GaslessSmartWallet());
    }

    /// @inheritdoc IGSWFactory
    function computeAddress(address owner) public view returns (address) {
        if (Address.isContract(owner)) {
            return address(0);
        }
        return gswImpl.predictDeterministicAddress(_getSalt(owner));
    }

    /// @inheritdoc IGSWFactory
    function deploy(address owner) external onlyEOA(owner) returns (address) {
        address _computedGSWAddress = computeAddress(owner);

        if (Address.isContract(_computedGSWAddress)) {
            // If GSW has already been deployed then just return it's address
            return _computedGSWAddress;
        } else {
            address deployedGSW = gswImpl.cloneDeterministic(_getSalt(owner));
            IGaslessSmartWallet(deployedGSW).initialize(owner);

            emit GSWDeployed(owner, deployedGSW);
            return deployedGSW;
        }
    }

    function _getSalt(address owner) internal pure returns (bytes32) {
        // only owner is used as salt
        // no extra salt is needed because even if another version of GSWFactory would be deployed,
        // clones take into account the deployers address (i.e. the factory address)
        return keccak256(abi.encode(owner));
    }
}

