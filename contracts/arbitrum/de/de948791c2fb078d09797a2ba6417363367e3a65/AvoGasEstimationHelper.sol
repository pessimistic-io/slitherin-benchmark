// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { Address } from "./Address.sol";

import { IAvoFactory } from "./IAvoFactory.sol";
import { IAvoWalletV3 } from "./IAvoWalletV3.sol";
import { IAvoMultisigV3 } from "./IAvoMultisigV3.sol";

// empty interface used for Natspec docs for nice layout in automatically generated docs:
//
/// @title  AvoGasEstimationsHelper v3.0.0
/// @notice Helps to estimate gas costs for execution of arbitrary actions in an Avocado smart wallet,
/// especially when the smart wallet is not deployed yet.
/// ATTENTION: Only supports AvoWallet version > 2.0.0
interface AvoGasEstimationsHelper_V3 {

}

interface IAvoWalletWithCallTargets is IAvoWalletV3 {
    function _callTargets(Action[] calldata actions_, uint256 id_) external payable;
}

interface IAvoMultisigWithCallTargets is IAvoMultisigV3 {
    function _callTargets(Action[] calldata actions_, uint256 id_) external payable;
}

contract AvoGasEstimationsHelper {
    using Address for address;

    error AvoGasEstimationsHelper__InvalidParams();

    /***********************************|
    |           STATE VARIABLES         |
    |__________________________________*/

    /// @notice AvoFactory that this contract uses to find or create Avocado smart wallet deployments
    IAvoFactory public immutable avoFactory;

    /// @notice cached AvoSafe bytecode to optimize gas usage
    //
    // @dev If this changes because of a AvoFactory (and AvoSafe change) upgrade,
    // then this variable must be updated through an upgrade deploying a new AvoGasEstimationsHelper!
    bytes32 public immutable avoSafeBytecode;

    /// @notice cached AvoMultiSafe bytecode to optimize gas usage
    //
    // @dev If this changes because of an AvoFactory (and AvoMultiSafe change) upgrade,
    // then this variable must be updated through an upgrade deploying a new AvoGasEstimationsHelper!
    bytes32 public immutable avoMultiSafeBytecode;

    /// @notice constructor sets the immutable `avoFactory` address
    /// @param avoFactory_ address of AvoFactory (proxy)
    constructor(IAvoFactory avoFactory_) {
        if (address(avoFactory_) == address(0)) {
            revert AvoGasEstimationsHelper__InvalidParams();
        }
        avoFactory = avoFactory_;

        // get AvoSafe & AvoSafeMultsig bytecode from factory.
        // @dev if a new AvoFactory is deployed (upgraded), a new AvoGasEstimationsHelper must be deployed
        // to update these bytecodes. See README for more info.
        avoSafeBytecode = avoFactory.avoSafeBytecode();
        avoMultiSafeBytecode = avoFactory.avoMultiSafeBytecode();
    }

    /// @notice estimate gas usage of `actions_` via smart wallet `._callTargets()`.
    ///         Deploys the Avocado smart wallet if necessary.
    ///         Can be used for versions > 2.0.0.
    ///         Note this gas estimation will not include the gas consumed in `.cast()` or in AvoForwarder itself
    /// @param  owner_         Avocado smart wallet owner
    /// @param  actions_       the actions to execute (target, data, value, operation)
    /// @param  id_            id for actions, e.g.
    ///                        0 = CALL, 1 = MIXED (call and delegatecall), 20 = FLASHLOAN_CALL, 21 = FLASHLOAN_MIXED
    /// @return totalGasUsed_       total amount of gas used
    /// @return deploymentGasUsed_  amount of gas used for deployment (or for getting the contract if already deployed)
    /// @return isAvoSafeDeployed_  boolean flag indicating if AvoSafe is already deployed
    /// @return success_            boolean flag indicating whether executing actions reverts or not
    function estimateCallTargetsGas(
        address owner_,
        IAvoWalletV3.Action[] calldata actions_,
        uint256 id_
    )
        external
        payable
        returns (uint256 totalGasUsed_, uint256 deploymentGasUsed_, bool isAvoSafeDeployed_, bool success_)
    {
        uint256 gasSnapshotBefore_ = gasleft();

        IAvoWalletWithCallTargets avoWallet_;
        // `_getDeployedAvoWallet()` automatically checks if AvoSafe has to be deployed
        // or if it already exists and simply returns the address
        (avoWallet_, isAvoSafeDeployed_) = _getDeployedAvoWallet(owner_, address(0));

        deploymentGasUsed_ = gasSnapshotBefore_ - gasleft();

        (success_, ) = address(avoWallet_).call{ value: msg.value }(
            abi.encodeCall(avoWallet_._callTargets, (actions_, id_))
        );

        totalGasUsed_ = gasSnapshotBefore_ - gasleft();
    }

    /// @notice estimate gas usage of `actions_` via smart wallet `._callTargets()` for a certain `avoWalletVersion_`.
    ///         Deploys the Avocado smart wallet if necessary.
    ///         Can be used for versions > 2.0.0.
    ///         Note this gas estimation will not include the gas consumed in `.cast()` or in AvoForwarder itself
    /// @param  owner_         Avocado smart wallet owner
    /// @param  actions_       the actions to execute (target, data, value, operation)
    /// @param  id_            id for actions, e.g.
    ///                        0 = CALL, 1 = MIXED (call and delegatecall), 20 = FLASHLOAN_CALL, 21 = FLASHLOAN_MIXED
    /// @param  avoWalletVersion_   Version of AvoWallet to deploy
    ///                             Note that this param has no effect if the wallet is already deployed
    /// @return totalGasUsed_       total amount of gas used
    /// @return deploymentGasUsed_  amount of gas used for deployment (or for getting the contract if already deployed)
    /// @return isAvoSafeDeployed_  boolean flag indicating if AvoSafe is already deployed
    /// @return success_            boolean flag indicating whether executing actions reverts or not
    function estimateCallTargetsGasWithVersion(
        address owner_,
        IAvoWalletV3.Action[] calldata actions_,
        uint256 id_,
        address avoWalletVersion_
    )
        external
        payable
        returns (uint256 totalGasUsed_, uint256 deploymentGasUsed_, bool isAvoSafeDeployed_, bool success_)
    {
        uint256 gasSnapshotBefore_ = gasleft();

        IAvoWalletWithCallTargets avoWallet_;
        // `_getDeployedAvoWallet()` automatically checks if AvoSafe has to be deployed
        // or if it already exists and simply returns the address
        (avoWallet_, isAvoSafeDeployed_) = _getDeployedAvoWallet(owner_, avoWalletVersion_);

        deploymentGasUsed_ = gasSnapshotBefore_ - gasleft();

        (success_, ) = address(avoWallet_).call{ value: msg.value }(
            abi.encodeCall(avoWallet_._callTargets, (actions_, id_))
        );

        totalGasUsed_ = gasSnapshotBefore_ - gasleft();
    }

    /// @notice estimate gas usage of `actions_` via smart wallet `._callTargets()`.
    ///         Deploys the Avocado smart wallet if necessary.
    ///         Note this gas estimation will not include the gas consumed in `.cast()` or in AvoForwarder itself
    /// @param  owner_         Avocado smart wallet owner
    /// @param  actions_       the actions to execute (target, data, value, operation)
    /// @param  id_            id for actions, e.g.
    ///                        0 = CALL, 1 = MIXED (call and delegatecall), 20 = FLASHLOAN_CALL, 21 = FLASHLOAN_MIXED
    /// @return totalGasUsed_       total amount of gas used
    /// @return deploymentGasUsed_  amount of gas used for deployment (or for getting the contract if already deployed)
    /// @return isDeployed_         boolean flag indicating if AvoMultiSafe is already deployed
    /// @return success_            boolean flag indicating whether executing actions reverts or not
    function estimateCallTargetsGasMultisig(
        address owner_,
        IAvoMultisigV3.Action[] calldata actions_,
        uint256 id_
    ) external payable returns (uint256 totalGasUsed_, uint256 deploymentGasUsed_, bool isDeployed_, bool success_) {
        uint256 gasSnapshotBefore_ = gasleft();

        IAvoMultisigWithCallTargets avoMultisig_;
        // `_getDeployedAvoMultisig()` automatically checks if AvoMultiSafe has to be deployed
        // or if it already exists and simply returns the address
        (avoMultisig_, isDeployed_) = _getDeployedAvoMultisig(owner_, address(0));

        deploymentGasUsed_ = gasSnapshotBefore_ - gasleft();

        (success_, ) = address(avoMultisig_).call{ value: msg.value }(
            abi.encodeCall(avoMultisig_._callTargets, (actions_, id_))
        );

        totalGasUsed_ = gasSnapshotBefore_ - gasleft();
    }

    /// @notice estimate gas usage of `actions_` via smart wallet `._callTargets()` for a certain `avoMultisigVersion_`.
    ///         Deploys the Avocado smart wallet if necessary.
    ///         Note this gas estimation will not include the gas consumed in `.cast()` or in AvoForwarder itself
    /// @param  owner_         Avocado smart wallet owner
    /// @param  actions_       the actions to execute (target, data, value, operation)
    /// @param  id_            id for actions, e.g.
    ///                        0 = CALL, 1 = MIXED (call and delegatecall), 20 = FLASHLOAN_CALL, 21 = FLASHLOAN_MIXED
    /// @param avoMultisigVersion_  Version of AvoMultisig to deploy
    ///                             Note that this param has no effect if the wallet is already deployed
    /// @return totalGasUsed_       total amount of gas used
    /// @return deploymentGasUsed_  amount of gas used for deployment (or for getting the contract if already deployed)
    /// @return isDeployed_         boolean flag indicating if AvoMultiSafe is already deployed
    /// @return success_            boolean flag indicating whether executing actions reverts or not
    function estimateCallTargetsGasWithVersionMultisig(
        address owner_,
        IAvoMultisigV3.Action[] calldata actions_,
        uint256 id_,
        address avoMultisigVersion_
    ) external payable returns (uint256 totalGasUsed_, uint256 deploymentGasUsed_, bool isDeployed_, bool success_) {
        uint256 gasSnapshotBefore_ = gasleft();

        IAvoMultisigWithCallTargets avoMultisig_;
        // `_getDeployedAvoMultisig()` automatically checks if AvoMultiSafe has to be deployed
        // or if it already exists and simply returns the address
        (avoMultisig_, isDeployed_) = _getDeployedAvoMultisig(owner_, avoMultisigVersion_);

        deploymentGasUsed_ = gasSnapshotBefore_ - gasleft();

        (success_, ) = address(avoMultisig_).call{ value: msg.value }(
            abi.encodeCall(avoMultisig_._callTargets, (actions_, id_))
        );

        totalGasUsed_ = gasSnapshotBefore_ - gasleft();
    }

    /***********************************|
    |              INTERNAL             |
    |__________________________________*/

    /// @dev gets, or if necessary deploys an AvoSafe for owner `from_` and returns the address
    /// @param from_                AvoSafe Owner
    /// @param avoWalletVersion_    Optional param to define a specific AvoWallet version to deploy
    /// @return                     the AvoSafe for the owner & boolean flag for if it was already deployed or not
    function _getDeployedAvoWallet(
        address from_,
        address avoWalletVersion_
    ) internal returns (IAvoWalletWithCallTargets, bool) {
        address computedAvoSafeAddress_ = _computeAvoSafeAddress(from_);
        if (Address.isContract(computedAvoSafeAddress_)) {
            return (IAvoWalletWithCallTargets(computedAvoSafeAddress_), true);
        } else {
            if (avoWalletVersion_ == address(0)) {
                return (IAvoWalletWithCallTargets(avoFactory.deploy(from_)), false);
            } else {
                return (IAvoWalletWithCallTargets(avoFactory.deployWithVersion(from_, avoWalletVersion_)), false);
            }
        }
    }

    /// @dev gets, or if necessary deploys, an AvoMultiSafe for owner `from_` and returns the address
    /// @param from_                AvoMultiSafe Owner
    /// @param avoMultisigVersion_  Optional param to define a specific AvoMultisig version to deploy
    /// @return                     the AvoMultiSafe for the owner & boolean flag for if it was already deployed or not
    function _getDeployedAvoMultisig(
        address from_,
        address avoMultisigVersion_
    ) internal returns (IAvoMultisigWithCallTargets, bool) {
        address computedAvoSafeAddress_ = _computeAvoSafeAddressMultisig(from_);
        if (Address.isContract(computedAvoSafeAddress_)) {
            return (IAvoMultisigWithCallTargets(computedAvoSafeAddress_), true);
        } else {
            if (avoMultisigVersion_ == address(0)) {
                return (IAvoMultisigWithCallTargets(avoFactory.deployMultisig(from_)), false);
            } else {
                return (
                    IAvoMultisigWithCallTargets(avoFactory.deployMultisigWithVersion(from_, avoMultisigVersion_)),
                    false
                );
            }
        }
    }

    /// @dev computes the deterministic contract address `computedAddress_` for a AvoSafe deployment for `owner_`
    function _computeAvoSafeAddress(address owner_) internal view returns (address computedAddress_) {
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(avoFactory), _getSalt(owner_), avoSafeBytecode)
        );

        // cast last 20 bytes of hash to address via low level assembly
        assembly {
            computedAddress_ := and(hash, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }

    /// @dev computes the deterministic contract address `computedAddress_` for a AvoSafeMultsig deployment for `owner_`
    function _computeAvoSafeAddressMultisig(address owner_) internal view returns (address computedAddress_) {
        // replicate Create2 address determination logic
        bytes32 hash = keccak256(
            abi.encodePacked(bytes1(0xff), address(avoFactory), _getSaltMultisig(owner_), avoMultiSafeBytecode)
        );

        // cast last 20 bytes of hash to address via low level assembly
        assembly {
            computedAddress_ := and(hash, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
        }
    }

    /// @dev gets the bytes32 salt used for deterministic deployment for `owner_`
    function _getSalt(address owner_) internal pure returns (bytes32) {
        // only owner is used as salt
        // no extra salt is needed because even if another version of AvoFactory would be deployed,
        // deterministic deployments take into account the deployers address (i.e. the factory address)
        // and the bytecode (-> difference between AvoSafe and AvoMultisig)
        return keccak256(abi.encode(owner_));
    }

    /// @dev gets the bytes32 salt used for deterministic Multisig deployment for `owner_`
    function _getSaltMultisig(address owner_) internal pure returns (bytes32) {
        // only owner is used as salt
        // no extra salt is needed because even if another version of AvoFactory would be deployed,
        // deterministic deployments take into account the deployers address (i.e. the factory address)
        // and the bytecode (-> difference between AvoSafe and AvoMultisig)
        return keccak256(abi.encode(owner_));
    }
}

