// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./draft-ERC20Permit.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./ISeparatePool.sol";

contract SeparatePool is ERC20Permit, ISeparatePool {
    IERC20 FUR;

    // Amount to mint/burn when selling/buying NFT
    uint256 public constant SWAP_MINT_AMOUNT = 1000e18;
    // Amount to mint/burn when locking/redeeming NFT
    uint256 public constant LOCK_MINT_AMOUNT = 500e18;
    uint256 public constant RELEASE_PUNISHMENT_AMOUNT = 300e18;

    address public immutable factory;
    address public immutable nft;
    // Transfer fee to income maker
    // Fees in this contract are in the form of F-X tokens
    address public incomeMaker;

    // Amount of F-X to mint on top of just 500 when locking
    uint256 lockMintBuffer;
    // Lock period in seconds
    uint256 public lockPeriod; 

    // Amount of FUR to pay
    uint256 buyFee = 100e18;
    uint256 lockFee = 150e18;

    // Pool admin
    address public owner;

    struct LockInfo {
        address locker;
        uint128 releaseTime;
        uint128 mintBuffer; // lockMintBuffer value WHEN NFT IS LOCKED
    }
    mapping(uint256 => LockInfo) public lockInfo;

    constructor(
        address _nftAddress,
        address _incomeMaker,
        address _fur,
        address _owner,
        string memory _tokenName,
        string memory _tokenSymbol
    ) ERC20Permit(_tokenName) ERC20(_tokenName, _tokenSymbol) {
        factory = msg.sender;
        incomeMaker = _incomeMaker;
        nft = _nftAddress;
        FUR = IERC20(_fur);
        owner = _owner;
        // 2 months lock period by default
        lockPeriod = 60 * 24 * 3600;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "SeparatePool: Not owner");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == factory, "SeparatePool: Not factory");
        _;
    }

    modifier batchLimit(uint256 _amount) {
        require(_amount < 10, "SeparatePool: 9 NFTs at most");
        _;
    }

    /**
     * @dev Get complete lock info of NFT
     */
    function getLockInfo(uint256 _id) public view returns (LockInfo memory) {
        return lockInfo[_id];
    }

    /**
     * @dev Change fee rate for buying NFT after governance voting
     */
    function setBuyFee(uint256 _newFee) external onlyOwner {
        buyFee = _newFee;
    }

    /**
     * @dev Change fee rate for locking NFT after governance voting
     */
    function setLockFee(uint256 _newFee) external onlyOwner {
        lockFee = _newFee;
    }

    function setLockMintBuffer(uint256 _newAmount) external onlyOwner {
        require(_newAmount <= 100e18, "SeparatePool: Buffer too large");
        lockMintBuffer = _newAmount;
    }

    function setLockPeriod(uint256 _periodInDays) external onlyOwner {
        lockPeriod = _periodInDays * 24 * 3600;
    }

    /**
     * @dev Change pool admin
     */
    function changeOwner(address _newOwner) external onlyFactory {
        address oldOwner = owner;
        owner = _newOwner;

        emit OwnerChanged(oldOwner, _newOwner);
    }

    function setFur(address _newFur) external onlyFactory {
        FUR = IERC20(_newFur);
    }

    function setIncomeMaker(address _newIncomeMaker) external onlyFactory {
        incomeMaker = _newIncomeMaker;
    }

    /**
     * @dev Sell single NFT and mint 1000 tokens immediately
     */
    function sell(uint256 _id) external {
        _sell(_id, true);
    }

    /**
     * @dev Sell multiple NFTs of same collection in one tx
     */
    function sellBatch(uint256[] calldata _ids) external batchLimit(_ids.length) {
        // Number of NFTs in list
        uint256 length = _ids.length;

        for (uint256 i; i < length; ) {
            // Mint total amount all at once, so _updateNow is false
            _sell(_ids[i], false);

            unchecked {
                ++i;
            }
        }

        _mint(msg.sender, SWAP_MINT_AMOUNT * length);
    }

    /**
     * @dev Buy single NFT and burn 1000 tokens immediately
     */
    function buy(uint256 _id) external {
        _buy(_id, true);
    }

    /**
     * @dev Buy multiple NFTs of same collection in one tx
     */
    function buyBatch(uint256[] calldata _ids) external batchLimit(_ids.length) {
        // Number of NFTs to buy
        uint256 length = _ids.length;

        uint256 burnTotal = SWAP_MINT_AMOUNT * length;
        uint256 feeTotal = buyFee * length;
        _burn(msg.sender, burnTotal);
        _chargeFee(feeTotal);

        for (uint256 i; i < length; ) {
            // Collected fee all at once, so _updateNow is false
            _buy(_ids[i], false);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Lock a single NFT
     */
    function lock(uint256 _id) external {
        _lock(_id, true, lockMintBuffer);
    }

    /**
     * @dev Lock multiple NFTs of same collection
     */
    function lockBatch(uint256[] calldata _ids) external batchLimit(_ids.length) {
        // Number of NFTs to lock
        uint256 length = _ids.length;

        uint256 _lockMintBuffer = lockMintBuffer;
        uint256 mintTotal = (LOCK_MINT_AMOUNT + _lockMintBuffer) * length;
        uint256 feeTotal = lockFee * length;
        _chargeFee(feeTotal);

        for (uint256 i; i < length; ) {
            // Collected fee all at once, so _updateNow is false
            _lock(_ids[i], false, _lockMintBuffer);

            unchecked {
                ++i;
            }
        }

        _mint(msg.sender, mintTotal);
    }

    /**
     * @dev Redeem locked NFT by paying 500 F-X
     */
    function redeem(uint256 _id) public {
        _redeem(_id, true);
    }

    /**
     * @dev Redeem multiple NFTs of same collection
     */
    function redeemBatch(uint256[] calldata _ids) external batchLimit(_ids.length) {
        uint256 length = _ids.length;

        uint256 burnTotal;
        for (uint256 i; i < length; ) {
            // Mint buffer may have changed between lockings 
            burnTotal += LOCK_MINT_AMOUNT + lockInfo[_ids[i]].mintBuffer;

            unchecked {
                ++i;
            }
        } 
        _burn(msg.sender, burnTotal);

        for (uint256 i; i < length; ) {
            _redeem(_ids[i], false);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Only 700 F-X is minted IN TOTAL to locker as a penalty
     * 
     * @dev Release NFT to public for buying. Mint F-X to locker and punishment 
     *      amount to income maker
     */
    function release(uint256 _id) external onlyOwner {
        require(lockInfo[_id].locker != address(0), "SeparatePool: NFT not locked.");
        require(lockInfo[_id].releaseTime < block.timestamp, "SeparatePool: Release time not yet reached.");

        address sendRemainingTo = lockInfo[_id].locker;
        uint256 mintBuffer = lockInfo[_id].mintBuffer;

        delete lockInfo[_id];

        _mint(sendRemainingTo, LOCK_MINT_AMOUNT - mintBuffer - RELEASE_PUNISHMENT_AMOUNT);
        _mint(incomeMaker, RELEASE_PUNISHMENT_AMOUNT);

        emit ReleasedNFT(_id);
    }

    /**
     * @dev Sell NFT to pool and get 1000 F-X
     * 
     * @param _updateNow Determines if minting is done immediately or after
     *        multiple calls (batched)
     */
    function _sell(uint256 _id, bool _updateNow) private {
        IERC721(nft).safeTransferFrom(msg.sender, address(this), _id);

        if (_updateNow) {
            _mint(msg.sender, SWAP_MINT_AMOUNT);
        }

        emit SoldNFT(_id, msg.sender);
    }

    /**
     * @dev Buy NFT from pool by paying 1000 F-X
     * 
     * @param _updateNow Determines if burning is done immediately or after
     *        multiple calls (batched)
     */
    function _buy(uint256 _id, bool _updateNow) private {
        require(lockInfo[_id].locker == address(0), "SeparatePool: NFT is locked");

        if (_updateNow) {
            _burn(msg.sender, SWAP_MINT_AMOUNT);

            _chargeFee(buyFee);
        }

        IERC721(nft).safeTransferFrom(address(this), msg.sender, _id);

        emit BoughtNFT(_id, msg.sender);
    }

    /**
     * @dev Lock NFT to pool for 60 days and get 500 F-X, paying 150 FUR as fees.
     *      
     * @param _updateNow Determines if burning is done immediately or after
     *        multiple calls (batched)
     * @param _lockMintBuffer Mint buffer amount at the moment of execution. 
     *        Passed as param to avoid cold storage access in every loop during 
     *        batch execution
     */
    function _lock(uint256 _id, bool _updateNow, uint256 _lockMintBuffer) private {
        IERC721(nft).safeTransferFrom(msg.sender, address(this), _id);

        if (_updateNow) {
            _chargeFee(lockFee);

            _mint(msg.sender, LOCK_MINT_AMOUNT + _lockMintBuffer);
        }

        lockInfo[_id].locker = msg.sender;
        uint256 releaseTime = block.timestamp + lockPeriod;
        lockInfo[_id].releaseTime = uint128(releaseTime);
        lockInfo[_id].mintBuffer = uint128(_lockMintBuffer);

        emit LockedNFT(_id, msg.sender, block.timestamp, releaseTime);
    }

    function _redeem(uint256 _id, bool _updateNow) private {
        require(lockInfo[_id].locker == msg.sender, "SeparatePool: Not locker");
        require(
            lockInfo[_id].releaseTime > block.timestamp,
            "SeparatePool: Already released"
        );

        if (_updateNow) _burn(msg.sender, LOCK_MINT_AMOUNT + lockInfo[_id].mintBuffer);

        delete lockInfo[_id];

        IERC721(nft).safeTransferFrom(address(this), msg.sender, _id);

        emit RedeemedNFT(_id, msg.sender);
    }

    function _chargeFee(uint256 _amount) private {
        // No fees before FUR is launched
        if (address(FUR) == address(0)) return;
        else FUR.transferFrom(msg.sender, incomeMaker, _amount);
    }

    function onERC721Received(address, address, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

