// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

interface IGaslessSmartWallet {
    function owner() external view returns (address);

    function gswNonce() external view returns (uint256);

    /// @notice             initializer called by factory after EIP-1167 minimal proxy clone deployment
    /// @param _owner       the owner (immutable) of this smart wallet
    function initialize(address _owner) external;

    /// @notice             returns the domainSeparator for EIP712 signature
    /// @return             the bytes32 domainSeparator for EIP712 signature
    function domainSeparatorV4() external view returns (bytes32);

    /// @notice             Verify the transaction is valid and can be executed.
    ///                     Does not revert and returns successfully if the input is valid.
    ///                     Reverts if any validation has failed. For instance, if params or either signature or gswNonce are incorrect.
    /// @param targets      the targets to execute the actions on
    /// @param datas        the data to be passed to the .call for each target
    /// @param values       the msg.value to be passed to the .call for each target. set to 0 if none
    /// @param signature    the EIP712 signature, should match keccak256(abi.encode(targets, datas, gswNonce, domainSeparatorV4()))
    ///                     see modifier validSignature
    /// @param validUntil   As EIP-2770: the highest block number the request can be forwarded in, or 0 if request validity is not time-limited
    ///                     Protects against relayers executing a certain transaction at a later moment not intended by the user, where it might
    ///                     have a completely different effect. (Given that the transaction is not executed right away for some reason)
    /// @param gas          As EIP-2770: an amount of gas limit to set for the execution
    ///                     Protects gainst potential gas griefing attacks / the relayer getting a reward without properly executing the tx completely
    ///                     See https://ronan.eth.limo/blog/ethereum-gas-dangers/
    /// @return             returns true if everything is valid, otherwise reverts
    function verify(
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values,
        bytes calldata signature,
        uint256 validUntil,
        uint256 gas
    ) external view returns (bool);

    /// @notice             executes arbitrary actions according to datas on targets
    ///                     if one action fails, the transaction doesn't revert. Instead the CastFailed event is emitted
    ///                     and no further action is executed. On success, emits CastExecuted event.
    /// @dev                validates EIP712 signature then executes a .call for every action.
    /// @param targets      the targets to execute the actions on
    /// @param datas        the data to be passed to the .call for each target
    /// @param values       the msg.value to be passed to the .call for each target. set to 0 if none
    /// @param signature    the EIP712 signature, should match keccak256(abi.encode(targets, datas, gswNonce, domainSeparatorV4()))
    ///                     see modifier validSignature
    /// @param validUntil   As EIP-2770: the highest block number the request can be forwarded in, or 0 if request validity is not time-limited
    ///                     Protects against relayers executing a certain transaction at a later moment not intended by the user, where it might
    ///                     have a completely different effect. (Given that the transaction is not executed right away for some reason)
    /// @param gas          As EIP-2770: an amount of gas limit to set for the execution
    ///                     Protects gainst potential gas griefing attacks / the relayer getting a reward without properly executing the tx completely
    ///                     See https://ronan.eth.limo/blog/ethereum-gas-dangers/
    function cast(
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values,
        bytes calldata signature,
        uint256 validUntil,
        uint256 gas
    ) external payable;
}

