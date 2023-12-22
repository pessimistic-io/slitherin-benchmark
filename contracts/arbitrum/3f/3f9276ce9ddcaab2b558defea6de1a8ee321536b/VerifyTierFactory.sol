// SPDX-License-Identifier: CAL
pragma solidity =0.8.10;

import {Factory} from "./Factory.sol";
import {VerifyTier} from "./VerifyTier.sol";

import "./Clones.sol";

/// @title VerifyTierFactory
/// @notice Factory for creating and deploying `VerifyTier` contracts.
contract VerifyTierFactory is Factory {
    /// Template contract to clone.
    /// Deployed by the constructor.
    address public immutable implementation;

    /// Build the reference implementation to clone for each child.
    constructor() {
        address implementation_ = address(new VerifyTier());
        emit Implementation(msg.sender, implementation_);
        implementation = implementation_;
    }

    /// @inheritdoc Factory
    function _createChild(bytes calldata data_)
        internal
        virtual
        override
        returns (address)
    {
        address verify_ = abi.decode(data_, (address));
        address clone_ = Clones.clone(implementation);
        VerifyTier(clone_).initialize(verify_);
        return clone_;
    }

    /// Typed wrapper for `createChild` with `Verify`.
    /// Use original `Factory` `createChild` function signature if function
    /// parameters are already encoded.
    ///
    /// @param verify_ `Verify` of the `VerifyTier` logic.
    /// @return New `VerifyTier` child contract address.
    function createChildTyped(address verify_) external returns (VerifyTier) {
        return VerifyTier(this.createChild(abi.encode(verify_)));
    }
}

