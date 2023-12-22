// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

import {Token} from "./Token.sol";
import {WrappedToken} from "./WrappedToken.sol";
import {Allowlist} from "./Allowlist.sol";
import {Base} from "./token_Base.sol";

/// @notice Controller contract for the rebasing token.
contract Controller is Base {
    /// @notice The token contract.
    Token public immutable token;
    /// @notice The token contract.
    WrappedToken public immutable wrappedToken;
    /// @notice The allowlist contract.
    Allowlist public allowlist;
    /// @notice The address of the minter contract.
    address public minter;

    error NotMinter();
    error NotAllowed();

    event SendToChain(uint16 indexed _dstChainId, address indexed sender, uint256 _amount);
    event ReceiveFromChain(uint16 indexed _srcChainId, address indexed _to, uint256 _amount);
    event SetMinter(address indexed minter);

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(Token _token, WrappedToken _wToken, address _lzEndpoint, uint16 _lzChainId) Base(_lzEndpoint, _lzChainId) {
        token = _token;
        wrappedToken = _wToken;
        allowlist = _token.allowlist();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Estimate the fee for bridging to the given chain.
    /// @dev Pass this fee in the bridge function.
    function estimateBridgeFee(uint16 _dstChainId, uint256 _amount, bool _useZro, bytes calldata _adapterParams)
        public
        view
        returns (uint256 nativeFee, uint256 zroFee)
    {
        bytes memory payload = abi.encode(PT_SEND, msg.sender, _amount);
        return lzEndpoint.estimateFees(_dstChainId, address(this), payload, _useZro, _adapterParams);
    }

    /// @notice Bridge tokens to another chain.
    /// @dev Bridging can only be done from and to msg.sender.
    function bridge(
        uint16 _dstChainId,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams,
        uint256 nativeFee
    ) public payable virtual {
        if (!allowlist.canTransact(msg.sender)) revert NotAllowed();
        _checkAdapterParams(_dstChainId, PT_SEND, _adapterParams, NO_EXTRA_GAS);
        token.burn(msg.sender, _amount);
        bytes memory lzPayload = abi.encode(PT_SEND, msg.sender, _amount);
        _lzSend(_dstChainId, lzPayload, _refundAddress, _zroPaymentAddress, _adapterParams, nativeFee);
        emit SendToChain(_dstChainId, msg.sender, _amount);
    }

    /// @notice Receive tokens from another chain.
    function _receive(bytes memory payload) internal override {
        (, address sender, uint256 amount) = abi.decode(payload, (uint16, address, uint256));
        if (!allowlist.canTransact(sender)) {
            // We add the address to the allowlist if it is currently unable to transact.
            // This is safe because we know the address can transact on the source chain.
            allowlist.allowAddress(sender, true);
        }
        token.mint(sender, amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 REBASE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Sets only the local rebase parameters.
    function setLocalRebase(uint32 change, uint32 startTime, uint32 endTime) external onlyOwner {
        token.setRebase(change, startTime, endTime);
    }

    /// @notice Estimate the fee for rebasing (across all chains).
    function estimateRebaseFee(
        uint32 change,
        uint32 startTime,
        uint32 endTime,
        bool useZro,
        bytes calldata adapterParams
    )
        public
        view
        returns (uint256[] memory nativeFees, uint256[] memory zroFees, uint256 totalNativeFees, uint256 totalZroFees)
    {
        return _estimatePropageteFees(abi.encode(PT_REBASE, change, startTime, endTime), useZro, adapterParams);
    }

    /// @notice Set the rebase parameters (across all chains).
    function setRebase(
        uint32 change,
        uint32 startTime,
        uint32 endTime,
        address payable refundAddress,
        address zroPaymentAddress,
        uint256[] calldata nativeFees
    ) external payable onlyOwner {
        token.setRebase(change, startTime, endTime);
        _propagate(abi.encode(PT_REBASE, change, startTime, endTime), refundAddress, zroPaymentAddress, nativeFees);
    }

    /// @notice Sets the rebase on the token.
    function _setRebase(bytes memory _payload) internal override {
        (, uint32 change, uint32 startTime, uint32 endTime) = abi.decode(_payload, (uint16, uint32, uint32, uint32));
        token.setRebase(change, startTime, endTime);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MERKLE ROOT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Sets only the local merkle root.
    function setLocalMerkleRoot(bytes32 newMerkleRoot) external onlyOwner {
        allowlist.setMerkleRoot(newMerkleRoot);
    }

    /// @notice Estimate the fee for setting the merkle root (across all chains).
    function estimateMerkleRootFee(bytes32 merkleRoot, bool useZro, bytes calldata adapterParams)
        public
        view
        returns (uint256[] memory nativeFees, uint256[] memory zroFees, uint256 totalNativeFees, uint256 totalZroFees)
    {
        return _estimatePropageteFees(abi.encode(PT_MERKLE, merkleRoot), useZro, adapterParams);
    }

    /// @notice Set the merkle root (across all chains).
    function setMerkleRoot(
        bytes32 newMerkleRoot,
        address payable refundAddress,
        address zroPaymentAddress,
        uint256[] calldata nativeFees
    ) external payable onlyOwner {
        allowlist.setMerkleRoot(newMerkleRoot);
        _propagate(abi.encode(PT_MERKLE, newMerkleRoot), refundAddress, zroPaymentAddress, nativeFees);
    }

    /// @notice Sets the merkle root on the allowlist.
    function _setMerkle(bytes memory payload) internal override {
        (, bytes32 merkleRoot) = abi.decode(payload, (uint16, bytes32));
        allowlist.setMerkleRoot(merkleRoot);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            TOKEN NAME FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setName(string memory _name, string memory _symbol) external onlyOwner {
        token.setName(_name, _symbol);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            TOKEN ISSUANCE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Directly mint tokens to an address.
    function mint(address to, uint256 amount) external onlyOwner {
        _addToAllowlist(to);
        token.mint(to, amount);
    }

    /// @notice Directly burn tokens from an address.
    function burn(address from, uint256 amount) external onlyOwner {
        token.burn(from, amount);
    }

    /// @notice Two step minging process.
    function mintFor(address account, uint256 amount) external onlyMinter returns (uint256 sharesMinted) {
        _addToAllowlist(account);
        return token.mint(minter, amount);
    }

    /// @notice Sets the minter.
    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
        emit SetMinter(_minter);
    }

    /// @notice Move wrapedToken from blocked user.
    function moveWrappedTokens(address from, address to, uint256 amount) external onlyOwner {
        wrappedToken.moveTokens(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                               TOKEN (UN)PAUSE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Pauses the token.
    function pause() external onlyOwner {
        token.pause();
    }

    /// @notice Unpauses the token.
    function unpause() external onlyOwner {
        token.unpause();
    }

    /*//////////////////////////////////////////////////////////////////////////
                               TOKEN OWNERSHIP TRANSFER
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Transfer ownership of the token.
    function changeController(address newController) external onlyOwner {
        /// @dev Controllers accross all chains must be updated together so that trusted remotes are set correctly.
        require(token.paused(), "Controller: token must be paused");
        token.transferOwnership(newController);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                ALLOWLIST FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Sets the allowlist contract.
    function setAllowlist(Allowlist newAllowlist) external onlyOwner {
        allowlist = newAllowlist;
        token.setAllowlist(newAllowlist);
    }

    /// @notice Sets the allow list required status.
    function setAllowlistRequired(bool required) external onlyOwner {
        allowlist.setAllowlistRequired(required);
    }

    /// @notice Sets the allow status of an account.
    function allowAddress(address account, bool allowed) external onlyOwner {
        allowlist.allowAddress(account, allowed);
    }

    /// @notice Sets the allow status of multiple accounts.
    function allowAddresses(address[] calldata accounts, bool[] calldata allowed) external onlyOwner {
        allowlist.allowAddresses(accounts, allowed);
    }

    /// @notice Blocks an account from interacting with the token.
    function blockAddress(address account, bool blocked) external onlyOwner {
        allowlist.blockAddress(account, blocked);
    }

    /// @notice Blocks multiple accounts from interacting with the token.
    function blockAddresses(address[] calldata accounts, bool[] calldata blocked) external onlyOwner {
        allowlist.blockAddresses(accounts, blocked);
    }

    /// @notice Adds an account to the allowlist.
    function _addToAllowlist(address account) internal {
        if (!allowlist.allowed(account)) {
            allowlist.allowAddress(account, true);
        }
    }

}

