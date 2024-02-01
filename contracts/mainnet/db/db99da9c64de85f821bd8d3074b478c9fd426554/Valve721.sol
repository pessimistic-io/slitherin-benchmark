// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERC721.sol";
import "./ERC721Holder.sol";

contract Valve721 is ERC721Holder, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    enum TransferStatus { Init, Sent, Cancelled }

    struct TokenTransfer {
        uint256 id;
        IERC721 token;
        address from;
        address to;
        uint256 tokenId;
        bytes data;
        uint256 expireAt;
        TransferStatus status;
        bytes32 exId;
    }

    uint256 public fee;
    address public feeRecipient;

    uint256 public validDuration;
    TokenTransfer[] public transfers;
    mapping(address => uint256[]) public transferCreators;
    mapping(address => uint256[]) public transferReceivers;
    mapping(bytes32 => uint256) public transferInfo;

    event Pause();
    event Unpause();
    event NewTransfer(
        address from,
        uint256 id,
        IERC721 token,
        address to,
        uint256 tokenId,
        bytes data,
        uint256 expireAt,
        TransferStatus status,
        bytes32 exId
    );
    event TransferAccepted(uint256 id, bytes32 exId);
    event TransferCancelled(uint256 id, bytes32 exId);

    function initialize() public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();

        validDuration = 5 minutes;
    }

    function getTransfers() external view returns (TokenTransfer[] memory) {
        return transfers;
    }

    function getTransferCount() external view returns (uint256) {
        return transfers.length;
    }

    function getUserTransferCount(address user) external view returns (uint256) {
        return transferCreators[user].length;
    }

    function getUserTransfers(address user) external view returns (TokenTransfer[] memory ts) {
        uint256 size = transferCreators[user].length;
        ts = new TokenTransfer[](size);

        for (uint256 index = 0; index < size; index++) {
            ts[index] = transfers[transferCreators[user][index]];
        }
    }

    function getUserSubTransfers(
        address user,
        uint256 fIndex,
        uint256 count
    ) external view returns (TokenTransfer[] memory ts, uint256 size) {
        size = transferCreators[user].length;

        uint256 realCount = count;

        if (fIndex + realCount >= size) {
            realCount = size - fIndex;
        }

        ts = new TokenTransfer[](realCount);

        for (uint256 index = 0; index < realCount; index++) {
            ts[index] = transfers[transferCreators[user][index + fIndex]];
        }
    }

    function getUserReceiveCount(address user) external view returns (uint256) {
        return transferReceivers[user].length;
    }

    function getUserReceives(address user) external view returns (TokenTransfer[] memory ts) {
        uint256 size = transferReceivers[user].length;
        ts = new TokenTransfer[](size);

        for (uint256 index = 0; index < size; index++) {
            ts[index] = transfers[transferReceivers[user][index]];
        }
    }

    function getUserSubReceives(
        address user,
        uint256 fIndex,
        uint256 count
    ) external view returns (TokenTransfer[] memory ts, uint256 size) {
        size = transferReceivers[user].length;

        uint256 realCount = count;

        if (fIndex + realCount >= size) {
            realCount = size - fIndex;
        }

        ts = new TokenTransfer[](realCount);

        for (uint256 index = 0; index < realCount; index++) {
            ts[index] = transfers[transferReceivers[user][index + fIndex]];
        }
    }

    /**
     * @notice create a new transfer
     *
     * @param token address of token
     * @param to address of to
     * @param tokenId id of erc721
     * @param data data of erc721
     */
    function createTransfer(
        IERC721 token,
        address to,
        uint256 tokenId,
        bytes memory data,
        bool isDirect
    ) external payable nonReentrant whenNotPaused {
        require(address(token) != address(0), "Invalid token address");
        require(msg.value == fee, "Invalid fee");
        TransferStatus status;
        if (isDirect) {
            status = TransferStatus.Sent;
            token.safeTransferFrom(msg.sender, to, tokenId, data);
            // send fee to fee recipient
            payable(feeRecipient).transfer(fee);
        } else {
            status = TransferStatus.Init;
            token.safeTransferFrom(msg.sender, address(this), tokenId, data);
        }

        uint256 id = transfers.length;
        bytes32 exId = keccak256(abi.encodePacked(msg.sender, id));

        transfers.push(
            TokenTransfer(
                id,
                token,
                msg.sender,
                to,
                tokenId,
                data,
                block.timestamp + validDuration,
                status,
                exId
            )
        );
        transferCreators[msg.sender].push(id);
        transferReceivers[to].push(id);
        transferInfo[exId] = id;

        emit NewTransfer(msg.sender, id, token, to, tokenId, data, block.timestamp + validDuration, status, exId);
    }

    /**
     * @notice acceptTransfer
     *
     * @param exId bytes32 exId
     */
    function acceptTransfer(bytes32 exId) external nonReentrant whenNotPaused {
        uint256 id = transferInfo[exId];
        TokenTransfer storage transfer = transfers[id];

        require(transfer.status == TransferStatus.Init && block.timestamp <= transfer.expireAt, "Invalid");
        require(msg.sender == transfer.to, "Invalid");

        // send token
        transfer.token.safeTransferFrom(address(this), transfer.to, transfer.tokenId, transfer.data);

        transfer.status = TransferStatus.Sent;

        // send fee to fee recipient
        payable(feeRecipient).transfer(fee);

        emit TransferAccepted(id, exId);
    }

    /**
     * @notice cancelTransfer
     *
     * @param exId bytes32 exId
     */
    function cancelTransfer(bytes32 exId) external nonReentrant whenNotPaused {
        uint256 id = transferInfo[exId];
        TokenTransfer storage transfer = transfers[id];

        require(transfer.status == TransferStatus.Init, "Invalid");
        require(msg.sender == transfer.from, "Invalid");

        // send token
        transfer.token.safeTransferFrom(address(this), transfer.from, transfer.tokenId, transfer.data);

        transfer.status = TransferStatus.Cancelled;

        // send fee
        payable(transfer.from).transfer(fee);

        emit TransferCancelled(id, exId);
    }

    //////////// Ownable functions /////////////
    /**
     * @notice setFeeInfo
     *
     * @param _feeRecipient address of feeRecipient
     * @param _fee fee amount for token transfer. For example, 0.01 eth on Ethereum, 0.1 bnb on BSC.
     */
    function setFeeInfo(address _feeRecipient, uint256 _fee) external onlyOwner {
        require(_feeRecipient != address(0), "Invalid feeRecipient");

        feeRecipient = _feeRecipient;
        fee = _fee;
    }

    /**
     * @notice update valid duration
     *
     * @param _validDuration expire seconds of transfer link
     */
    function setValidDuration(uint256 _validDuration) external onlyOwner {
        validDuration = _validDuration;
    }

    /**
     * @notice Triggers stopped state
     * @dev Only possible when contract not paused.
     */
    function pause() external onlyOwner whenNotPaused {
        _pause();
        emit Pause();
    }

    /**
     * @notice Returns to normal state
     * @dev Only possible when contract is paused.
     */
    function unpause() external onlyOwner whenPaused {
        _unpause();
        emit Unpause();
    }
}

