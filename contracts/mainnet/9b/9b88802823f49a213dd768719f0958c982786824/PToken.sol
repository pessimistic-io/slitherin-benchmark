// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./ERC20Upgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./IERC721MetadataUpgradeable.sol";
import "./IPTokenFactory.sol";
import "./TransferHelper.sol";
import "./PTokenStorage.sol";

/**
 * @title ptoken contract
 * @notice Supports NFT fractionalization, redemption, etc.
 * @author Pawnfi
 */
contract PToken is ERC20Upgradeable, ERC721HolderUpgradeable, ReentrancyGuardUpgradeable, PTokenStorage {
    using SafeMathUpgradeable for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    /**
     * @notice Initialize contract
     * @param nftAddress_ NFT address
     */    
    function initialize(address nftAddress_) external initializer {
        __ERC20_init(
            string(abi.encodePacked("Pawnfi ", IERC721MetadataUpgradeable(nftAddress_).name())),
            string(abi.encodePacked("P-", IERC721MetadataUpgradeable(nftAddress_).symbol()))
        );
        __ERC721Holder_init();
        __ReentrancyGuard_init();
        factory = msg.sender;
        nftAddress = nftAddress_;
        pieceCount = INftController(IPTokenFactory(msg.sender).controller()).pieceCount();

        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name())),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    /**
     * @notice EIP712 signature authorization method
     * @param owner Initiator address
     * @param spender Recipient address
     * @param value token amount
     * @param deadline The deadline
     * @param v Derived from signature information
     * @param r Derived from signature information
     * @param s Derived from signature information   
     */
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external virtual override {
        require(deadline >= block.timestamp, 'EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }

    /**
     * @notice Deposit (lock) Nft
     * @param nftIds nft list
     * @return tokenAmount ptoken amount
     */
    function deposit(uint256[] memory nftIds) external virtual override returns (uint256 tokenAmount) {
        return deposit(nftIds, 0);
    }

    /**
     * @notice Deposit (lock) Nft
     * @dev blockNumber = 0，Nft can be randomly swapped，blockNumber > 0, only within current block > blockNumber, can be specifically swapped
     * @param nftIds nft list
     * @param blockNumber The block height at which the lock-up expires
     * @return tokenAmount ptoken amount
     */
    function deposit(uint256[] memory nftIds, uint256 blockNumber) public virtual override nonReentrant returns (uint256 tokenAmount) {
        address msgSender = msg.sender;
        uint256 length = nftIds.length;
        require(length > 0, "SIZE ERR");
        address nftAddr = nftAddress;

        for(uint256 i = 0; i < length; i++) {
            uint256 nftId = nftIds[i];
            INftController.Action action = INftController.Action.STAKING;
            if(blockNumber == 0) {
                action = INftController.Action.FREEDOM;
                _allRandID.add(nftId);
            }
            require(getNftController().supportedNftId(msgSender, nftAddr, nftId, action), 'ID NOT ALLOW');

            NftInfo memory nftInfo = getNftInfo(nftId);
            nftInfo.startBlock = block.number;
            nftInfo.endBlock = blockNumber;
            nftInfo.userAddr = msgSender;
            nftInfo.action = action;
            TransferHelper.transferInNonFungibleToken(IPTokenFactory(factory).nftTransferManager(), nftAddress, msgSender, address(this), nftId);
            _allInfo[nftId] = nftInfo;
        }

        tokenAmount = pieceCount.mul(length);
        _mint(msgSender, tokenAmount);
        emit Deposit(msgSender, nftIds, blockNumber);
    }

    /**
     * @notice ptoken swap random NFT
     * @param nftIdCount NFT amount
     * @return nftIds nftId list
     */
    function randomTrade(uint256 nftIdCount) public virtual override nonReentrant returns (uint256[] memory nftIds) {
        address msgSender = msg.sender;
        address nftAddr = nftAddress;
        require(nftIdCount > 0 && nftIdCount <= getRandNftCount(), 'NO ID');

        INftController nftController = getNftController();
        (uint256 randFee, ) = nftController.getFeeInfo(nftAddr);
        uint256 fee = _collectFee(msgSender, randFee, nftIdCount);

        nftIds = new uint256[](nftIdCount);

        for(uint256 i = 0; i < nftIdCount; i++) {
            uint256 tokenIndex = nftController.getRandoms(nftAddr, getRandNftCount());
            uint256 nftId = getRandNft(tokenIndex);
            _tradeCore(nftId, msgSender);
            nftIds[i] = nftId;
        }
        emit RandomTrade(msgSender, nftIdCount, fee, nftIds);
        return nftIds;
    }

    /**
     * @notice ptoken swap specific NFT
     * @param nftIds nftId list
     */
    function specificTrade(uint256[] memory nftIds) public virtual override nonReentrant {
        address msgSender = msg.sender;
        uint256 nftIdCount = nftIds.length;
        require(nftIdCount > 0, 'SIZE ERR');
        (, uint256 noRandFee) = getNftController().getFeeInfo(nftAddress);
        uint256 fee = _collectFee(msgSender, noRandFee, nftIdCount);

        for(uint i = 0; i < nftIdCount; i++) {
            uint256 nftId = nftIds[i];
            _tradeCore(nftId, msgSender);
        }
        emit SpecificTrade(msgSender, nftIds.length, fee, nftIds);
    }

    function _tradeCore(uint256 nftId, address sender) internal {
        NftInfo memory nftInfo = getNftInfo(nftId);
        if(nftInfo.action == INftController.Action.FREEDOM) {
            require(_allRandID.remove(nftId), "nftId is not in the random list");
        } else {
            require(nftInfo.endBlock < block.number,'STATUS ERR');
        }
        _delData(nftId, sender);
    }

    /**
     * @notice Charge swap fee
     * @param sender Sender
     * @param fee Swap fee for one NFT
     * @param nftIdCount nftId amount
     */
    function _collectFee(address sender, uint256 fee, uint256 nftIdCount) internal returns (uint256) {
        uint256 tokenAmount = pieceCount.mul(nftIdCount);
        uint256 totalFee = fee.mul(nftIdCount);//Calculate the fees of NFTs

        _transfer(sender, address(this), tokenAmount.add(totalFee));
        _burn(address(this), tokenAmount);
        _transfer(address(this), IPTokenFactory(factory).feeTo(), totalFee); //Transfer out fees
        return totalFee;
    }

    /**
     * @notice Withdraw locked Nft
     * @param nftIds nftId list
     * @return tokenAmount token amount
     */
    function withdraw(uint256[] memory nftIds) public virtual override nonReentrant returns (uint256 tokenAmount) {
        address msgSender = msg.sender;
        uint256 length = nftIds.length;
        require(length > 0, "SIZE ERR");

        tokenAmount = pieceCount.mul(length);
        _burn(msgSender, tokenAmount);

        for(uint256 i = 0; i < length; i++) {
            uint256 nftId = nftIds[i];
            NftInfo memory nftInfo = getNftInfo(nftId);
            require(nftInfo.userAddr == msgSender, 'USER NOT ALLOW');//Must be lock initiator
            require(nftInfo.startBlock < block.number, "prohibit same block operate");
            require(nftInfo.action == INftController.Action.STAKING && nftInfo.endBlock >= block.number, "Status error");

            _delData(nftId, msgSender);
        }
        emit Withdraw(msgSender, nftIds);
    }

    /**
     * @notice Transfer NFT to receiver
     * @param nftId nftId
     * @param receipient Receiver
     */
    function _delData(uint256 nftId, address receipient) internal {
        delete _allInfo[nftId];
        TransferHelper.transferOutNonFungibleToken(IPTokenFactory(factory).nftTransferManager(), nftAddress, address(this), receipient, nftId);
    }

    /**
     * @notice Release locked NFT
     * @dev nft status from Staking to Free
     * @param nftIds nftId list
     */
    function convert(uint256[] memory nftIds) public virtual override nonReentrant {
        for(uint256 i = 0; i < nftIds.length; i++) {
            uint256 nftId = nftIds[i];
            NftInfo memory lockInfo = getNftInfo(nftId);
            require(lockInfo.userAddr == msg.sender, 'USER NOT ALLOW');//Must be lock initiator
            require(lockInfo.action == INftController.Action.STAKING, "Status error");
            lockInfo.action = INftController.Action.FREEDOM;
            _allInfo[nftId] = lockInfo;
            _allRandID.add(nftId);
        }
        emit Convert(msg.sender, nftIds);
    }
 
    /**
     * @notice Get deposited NFT information
     * @param nftId nftId
     * @return NftInfo Nft Info
     */
    function getNftInfo(uint256 nftId) public view virtual override returns (NftInfo memory) {
        return _allInfo[nftId];
    }

    /**
     * @notice Get the length of random NFT list
     * @return uint256 length
     */
    function getRandNftCount() public view virtual override returns (uint256) {
        return _allRandID.length();
    }

    /**
     * @notice Get NFT ID index
     * @param index Index
     * @return uint256 nftId
     */
    function getRandNft(uint256 index) public view virtual override returns (uint256) {
        return _allRandID.at(index);
    }

    /**
     * @notice Get nft controller address
     * @return address nft controller address
     */
    function getNftController() public view virtual override returns (INftController) {
        return INftController(IPTokenFactory(factory).controller());
    }
}
