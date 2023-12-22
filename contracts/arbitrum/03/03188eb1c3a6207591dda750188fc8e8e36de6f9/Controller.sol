// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import {Token} from "./Token.sol";
import {Whitelist} from "./Whitelist.sol";
import {Base} from "./token_Base.sol";

contract Controller is Base {
    Token public immutable token;
    Whitelist public whitelist;
    address public minter;

    error NotMinter();

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

    constructor(Token _token, address _lzEndpoint, uint16 _lzChainId) Base(_lzEndpoint, _lzChainId) {
        token = _token;
        whitelist = _token.whitelist();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   BRIDGE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function estimateBridgeFee(uint16 _dstChainId, uint256 _amount, bool _useZro, bytes calldata _adapterParams)
        public
        view
        returns (uint256 nativeFee, uint256 zroFee)
    {
        bytes memory payload = abi.encode(PT_SEND, msg.sender, _amount);
        return lzEndpoint.estimateFees(_dstChainId, address(this), payload, _useZro, _adapterParams);
    }

    // Bridging can only be done from and to msg.sender.
    function bridge(
        uint16 _dstChainId,
        uint256 _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) public payable virtual {
        _checkAdapterParams(_dstChainId, PT_SEND, _adapterParams, NO_EXTRA_GAS);
        token.burn(msg.sender, _amount);
        bytes memory lzPayload = abi.encode(PT_SEND, msg.sender, _amount);
        _lzSend(_dstChainId, lzPayload, _refundAddress, _zroPaymentAddress, _adapterParams, msg.value);
        emit SendToChain(_dstChainId, msg.sender, _amount);
    }

    function _receive(bytes memory payload) internal override {
        (, address sender, uint256 amount) = abi.decode(payload, (uint16, address, uint256));
        if (!whitelist.isWhitelisted(sender)) {
            whitelist.setDirectWhitelist(sender, true);
        }
        token.mint(sender, amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 REBASE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

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

    function setLocalRebase(uint32 change, uint32 startTime, uint32 endTime) external onlyOwner {
        token.setRebase(change, startTime, endTime);
    }

    function _setRebase(bytes memory _payload) internal override {
        (, uint32 change, uint32 startTime, uint32 endTime) = abi.decode(_payload, (uint16, uint32, uint32, uint32));
        token.setRebase(change, startTime, endTime);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MERKLE ROOT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function estimateMerkleRootFee(bytes32 merkleRoot, bool useZro, bytes calldata adapterParams)
        public
        view
        returns (uint256[] memory nativeFees, uint256[] memory zroFees, uint256 totalNativeFees, uint256 totalZroFees)
    {
        return _estimatePropageteFees(abi.encode(PT_MERKLE, merkleRoot), useZro, adapterParams);
    }

    function setMerkleRoot(
        bytes32 newMerkleRoot,
        address payable refundAddress,
        address zroPaymentAddress,
        uint256[] calldata nativeFees
    ) external payable onlyOwner {
        whitelist.setMerkleRoot(newMerkleRoot);
        _propagate(abi.encode(PT_MERKLE, newMerkleRoot), refundAddress, zroPaymentAddress, nativeFees);
    }

    function setLocalMerkleRoot(bytes32 newMerkleRoot) external onlyOwner {
        whitelist.setMerkleRoot(newMerkleRoot);
    }

    function _setMerkle(bytes memory payload) internal override {
        (, bytes32 merkleRoot) = abi.decode(payload, (uint16, bytes32));
        whitelist.setMerkleRoot(merkleRoot);
    }

    /*//////////////////////////////////////////////////////////////////////////
                               MINT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function mint(address to, uint256 amount) external onlyOwner {
        _whitelist(to);
        token.mint(to, amount);
    }

    function mintToVault(address user, uint256 amount) external onlyMinter returns (uint256 sharesMinted) {
        _whitelist(user);
        return token.mint(minter, amount);
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
        emit SetMinter(_minter);
    }

    /*//////////////////////////////////////////////////////////////////////////
                               (UN)PAUSE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function pause() external onlyOwner {
        token.pause();
    }

    function unpause() external onlyOwner {
        token.unpause();
    }

    /*//////////////////////////////////////////////////////////////////////////
                               OWNERSHIP TRANSFER
    //////////////////////////////////////////////////////////////////////////*/

    // Controllers accross all chains must be updated simultaneously (set trusted remotes).
    function changeController(address newController) external onlyOwner {
        require(token.paused(), "Controller: token must be paused");
        token.setOwner(newController);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            WHITELIST FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function setWhitelist(Whitelist newWhitelist) external onlyOwner {
        whitelist = newWhitelist;
        token.setWhitelist(newWhitelist);
    }

    function setDirectWhitelist(address account, bool whitelisted) external onlyOwner {
        whitelist.setDirectWhitelist(account, whitelisted);
    }

    function setDirectWhitelists(address[] calldata accounts, bool[] calldata whitelisted) external onlyOwner {
        whitelist.setDirectWhitelists(accounts, whitelisted);
    }

    function _whitelist(address account) internal {
        if (!whitelist.isWhitelisted(account)) {
            whitelist.setDirectWhitelist(account, true);
        }
    }
}

