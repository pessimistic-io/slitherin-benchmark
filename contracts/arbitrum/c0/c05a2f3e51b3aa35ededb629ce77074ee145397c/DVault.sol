// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Initializable.sol";
import "./IERC20.sol";
import "./TransferHelper.sol";
import "./SupportedTokens.sol";
import "./IERC165-SupportsInterface.sol";
import "./DVaultConfig.sol";



interface IERC721 {

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external payable;
    function transferFrom(address _from, address _to, uint256 _tokenId) external payable;
    function balanceOf(address _owner) external view returns (uint256);
}

interface EverRiseNFT is IERC721 {

    function withdrawRewards() external;
    function unclaimedRewardsBalance(address) external view returns (uint256);
    function getTotalRewards(address) external view returns (uint256);
}

interface IERC1155 {

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) external; 
    function safeBatchTransferFrom(address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external;
}

interface IERC721Receiver {

    function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes calldata _data) external returns(bytes4);
}

interface IERC1155Receiver is IERC165 {
    function onERC1155Received(address _operator, address from, uint256 id, uint256 value, bytes calldata data) external returns(bytes4);
    function onERC1155BatchReceived(address operator, address from, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external returns(bytes4);
}

contract DVault is Initializable, IERC721Receiver, IERC1155Receiver {
    using TransferHelper for IERC20;

    enum VaultStatus {
        LOCKED,
        UNLOCKED
    }

    enum BlockStatus {
        FALSE,
        TRUE
    }

    enum TokenType {
        ERC721,
        ERC1155
    }

    struct NFTList {
        address token;
        uint256 tokenId;
        TokenType tokenType;
        uint256 amount;
    }

    struct Balance {
        address token;
        uint256 balance;
        uint8 decimals;
    }

    struct VaultDetails {
        string name;
        address owner1;
        address owner2;
        string uri;
        VaultStatus owner1Status;
        VaultStatus owner2Status;
        VaultStatus status;
        uint256 lockTime;
        uint256 lockInitiatedTime;
        address lockInitiatedAddress;
        uint256 unlockInitiatedTime;
        bool owner1BlockStatus;
        bool owner2BlockStatus;
    }

    string public _name;
    address public _owner1;
    address public _owner2;
    string public _uri;
    DVaultConfig _vaultConfig;
    address public _factory;
    uint256 public deadline;
    uint256 public deadlineInitiated;
    address deadlineInitiatedOwner;

    SupportedTokens public _globalList;
    mapping (address => bool) _supportedTokens;
    address[] _tokensList;
    uint256 public _unlockInitiatedTime;

    VaultStatus _vaultStatus;
    VaultStatus _owner1Status;
    VaultStatus _owner2Status;
    mapping(address => bool) _ownerBlockStatus;

    error CurrentlyLocked(); //0x34ae7439
    error CurrentlyUnLocked(); //0xc799605c
    error TokenNotSupported(); //0x3dd1b305
    error NotZeroAddress(); //0x66385fa3
    error FailedETHSend(); //0xaf3f2195
    error InsufficientBalance(); //0xf4d678b8
    error UnAuthorized(); //0xbe245983
    error TimeLocked(); //0x56f38557
    error AlreadyTimeLocked(); //0x6341b790
    error NotEnoughRewards(); //0x1e6918b1
    error BlockedOwner(); //0x1c248638
    error AlreadyBlocked(); //0x196a151c
    error InvalidOwner(); //0x49e27cff

    event OwnerUpdated(address indexed prevOwner, address indexed newOwner);

    constructor() {}

    function initialize(string memory name, address owner1, address owner2, address factory, string memory uri, DVaultConfig vaultConfig, SupportedTokens globalList) public initializer {
        _name = name;
        _owner1 = owner1;
        _owner2 = owner2;
        _factory = factory;
        _uri = uri;
        _vaultConfig = vaultConfig;
        _globalList = globalList;
    }

    receive() external payable  {}

    fallback() external payable {}

    modifier authorizedOwner() {
        if (msg.sender != _owner1 && msg.sender != _owner2) revert UnAuthorized();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != _factory) revert UnAuthorized();
        _;
    }

    modifier notBlocked() {
        if (_ownerBlockStatus[msg.sender]) revert BlockedOwner();
        _;
    }

    modifier supportedToken(address token) {
        if (token != address(0) && !isTokenSupported(token)) revert TokenNotSupported();
        _;
    }

    modifier unLocked() {
        if (_vaultStatus == VaultStatus.LOCKED) revert CurrentlyLocked();
        _;
    }

    modifier locked() {
        if (_vaultStatus == VaultStatus.UNLOCKED) revert CurrentlyUnLocked();
        _;
    }

    modifier completelyLocked() {
        if (_owner1Status == VaultStatus.UNLOCKED || _owner2Status == VaultStatus.UNLOCKED) revert CurrentlyUnLocked();
        _;
    }

    modifier validAmount(uint256 amount) {
        require(amount > 0, "Amount should be greater than 0");
        _;
    }

    function addSupportedToken(address token) external authorizedOwner notBlocked {
        require (!_supportedTokens[token], "Already Supported");
        _supportedTokens[token] = true;
        _tokensList.push(token);
    }

    function getTokensList() public view returns (address[] memory) {
        return _tokensList;
    }

    function isSupportedToken(address token) public view returns (bool) {
        return _supportedTokens[token];
    }

    function isTokenSupported(address token) public view returns (bool) {
        return isSupportedToken(token) || SupportedTokens(_globalList).isSupportedToken(token);
    }

    function updateName(string memory name) external authorizedOwner notBlocked {
        _name = name;
    }

    function updateLogo(string memory uri) external authorizedOwner notBlocked {
        _uri = uri;
    }

    function isAuthorizedOwner(address addr) external view returns (bool) {
        return ((addr == _owner1 || addr == _owner2) && !_ownerBlockStatus[addr]);
    }

    function initiateTimeLock(uint256 time) external authorizedOwner completelyLocked {
        if (deadline > block.timestamp) revert AlreadyTimeLocked();
        deadlineInitiatedOwner = msg.sender;
        deadlineInitiated = time + block.timestamp;
    }

    function approveTimeLock() external authorizedOwner completelyLocked {
        if (msg.sender == deadlineInitiatedOwner) revert UnAuthorized();
        if (_vaultConfig.getCollectTimelockFee()) {
            _collectFee(_vaultConfig.getTimeLockFeeTokenAddress(), _vaultConfig.getFeeAddress(), _vaultConfig.getTimeLockFeeAmount());
        }
        deadline = deadlineInitiated;
        deadlineInitiated = 0;
    }

    function rejectTimeLock() external authorizedOwner completelyLocked {
        deadlineInitiated = 0;
    }

    function blockOtherOwner() external authorizedOwner notBlocked locked {

        if (msg.sender == _owner1) {
            if (_owner2Status == VaultStatus.LOCKED) revert UnAuthorized();
            if (_ownerBlockStatus[_owner2]) revert AlreadyBlocked();
            _ownerBlockStatus[_owner2] = true;
        } else {
            if (_owner1Status == VaultStatus.LOCKED) revert UnAuthorized();
            if (_ownerBlockStatus[_owner1]) revert AlreadyBlocked();
            _ownerBlockStatus[_owner1] = true;
        }
    }

    function updateOwner(address oldOwner, address newOwner) external onlyFactory locked {
        if (oldOwner != _owner1 && oldOwner != _owner2) revert InvalidOwner();
        if (newOwner == _owner1 || newOwner == _owner2) revert InvalidOwner();
        if (oldOwner == _owner1) {
            if (_owner1Status == VaultStatus.LOCKED) revert CurrentlyLocked();
            _owner1 = newOwner;
            _owner1Status = VaultStatus.LOCKED;
        } else if (oldOwner == _owner2) {
            if (_owner2Status == VaultStatus.LOCKED) revert CurrentlyLocked();
            _owner2 = newOwner;
            _owner2Status = VaultStatus.LOCKED;
        }
        emit OwnerUpdated(oldOwner, newOwner);
    }

    function getLockTime() public view returns (uint256) {
        if (deadline > block.timestamp) return deadline - block.timestamp;
        return 0;
    }

    function lockVault() external authorizedOwner notBlocked unLocked {
        _owner1Status = VaultStatus.LOCKED;
        _owner2Status = VaultStatus.LOCKED;
        _vaultStatus = VaultStatus.LOCKED;
    }

    function updateLockStatus() external authorizedOwner notBlocked locked {
        if (msg.sender == _owner1) {
            if (_owner1Status == VaultStatus.LOCKED) revert CurrentlyLocked();
            if (block.timestamp > _unlockInitiatedTime + 365 days) {
                _owner2Status = VaultStatus.UNLOCKED;
                _vaultStatus = VaultStatus.UNLOCKED;
            }
        } else {
            if (_owner2Status == VaultStatus.LOCKED) revert CurrentlyLocked();
            if (block.timestamp > _unlockInitiatedTime + 365 days) {
                _owner1Status = VaultStatus.UNLOCKED;
                _vaultStatus = VaultStatus.UNLOCKED;
            }
        }
    }

    function unlockVault() external authorizedOwner locked {
        if (block.timestamp < deadline) revert TimeLocked();
        if (_vaultConfig.getCollectUnlockFee()) {
            _collectFee(_vaultConfig.getUnlockVaultFeeTokenAddress(), _vaultConfig.getFeeAddress(), _vaultConfig.getUnlockVaultFeeAmount());
        }

        if (msg.sender == _owner1) _owner1Status = VaultStatus.UNLOCKED;
        else _owner2Status = VaultStatus.UNLOCKED;

        _unlockInitiatedTime = block.timestamp;

        if (_owner1Status == VaultStatus.UNLOCKED && _owner2Status == VaultStatus.UNLOCKED) _vaultStatus = VaultStatus.UNLOCKED;
    }

    function isContract(address addr) public view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }

    function getUnlockInitiatedTime() public view returns (uint256) {
        return block.timestamp - _unlockInitiatedTime;
    }

    function getTimeLockInitiatedTime() public view returns (uint256) {
        if (deadlineInitiated > block.timestamp) return deadlineInitiated - block.timestamp;
        return 0;
    }

    function approveToken(address token, uint256 amount) external authorizedOwner notBlocked unLocked {
        require(_globalList.isSupportedToken(token), "Token is not supported");
        IERC20(token).approve(_factory, amount);
    }

    function _collectFee(address token, address feeAddress, uint256 amount) internal {
        bool isNFTExists;
        if (_vaultConfig.getCheckForNFT() && IERC721(_vaultConfig.getNFTAddress()).balanceOf(address(this)) > 0) isNFTExists = true;
        if (!isNFTExists) {
            if (token == address(0)) {
                if (address(this).balance < amount) revert InsufficientBalance();
                _transfer(feeAddress, amount);
            } else {
                if (IERC20(token).balanceOf(address(this)) < amount) revert InsufficientBalance();
                IERC20(token).safeTransfer(feeAddress, amount);
            }
        }
    }

    function transferOut(address token, address to, uint256 amount) external authorizedOwner notBlocked unLocked supportedToken(token) validAmount(amount) {        
        if (token == address(0)) {
            if (address(this).balance < amount) revert InsufficientBalance();
            _transfer(to, amount);
        } else {
            if (IERC20(token).balanceOf(address(this)) < amount) revert InsufficientBalance();
            IERC20(token).safeTransfer(to, amount);
        }
    }

    function transferNFTOut(address token, address to, uint256 tokenId, TokenType tokenType, uint256 amount) public authorizedOwner notBlocked unLocked validAmount(amount) {
        if (tokenType == TokenType.ERC721) {
            IERC721(token).safeTransferFrom(address(this), to, tokenId);

        } else if (tokenType == TokenType.ERC1155) {
            IERC1155(token).safeTransferFrom(address(this), to, tokenId, amount, "");
        }
    }

    function transferMultipleNFTsOut(NFTList[] calldata nftList, address to) external authorizedOwner notBlocked unLocked {
        uint256 length = nftList.length;
        for (uint i; i < length; i++) {
            transferNFTOut(nftList[i].token, to, nftList[i].tokenId, nftList[i].tokenType, nftList[i].amount);
        }
    }

    function _transfer(address to, uint256 amount) internal {
        if (to == address(0)) revert NotZeroAddress();
        (bool success, ) = payable(to).call{value: amount}("");
        
        if (!success) revert FailedETHSend();
    }

    function getUserTokens() external view returns (address[] memory) {
        return getTokensList();
    }

    function getGlobalTokens() external view returns (address[] memory) {
        return SupportedTokens(_globalList).getTokensList();
    }

    function getVaultDetails() external view returns (VaultDetails memory) {
        return VaultDetails(_name, _owner1, _owner2, _uri, _owner1Status, _owner2Status, _vaultStatus, getLockTime(), getTimeLockInitiatedTime(), deadlineInitiatedOwner, getUnlockInitiatedTime(), _ownerBlockStatus[_owner1], _ownerBlockStatus[_owner2]);
    }

    function claimRewards() external authorizedOwner notBlocked {
        uint256 availableRewards = unclaimedRewardsBalance();
        if (availableRewards == 0) revert NotEnoughRewards();

        EverRiseNFT(_vaultConfig.getEverRiseNFTAddress()).withdrawRewards();
    }

    function unclaimedRewardsBalance() public view returns (uint256) {
        return EverRiseNFT(_vaultConfig.getEverRiseNFTAddress()).unclaimedRewardsBalance(address(this));
    }

    function totalRewards() public view returns (uint256) {
        return EverRiseNFT(_vaultConfig.getEverRiseNFTAddress()).getTotalRewards(address(this));
    }

    function onERC721Received(address, address, uint256, bytes calldata ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata ) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }
}
