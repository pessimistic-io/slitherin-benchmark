// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./ERC20.sol";
import "./ERC1155.sol";
import "./ERC1155Upgradeable.sol";
import "./ERC1155SupplyUpgradeable.sol";
import "./ERC2981Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Math.sol";
import {ECDSA} from "./ECDSA.sol";
import "./UUPSUpgradeable.sol";
import "./IMysteryBox.sol";

/// @title LUAG MysteryBox
/// @author Albert
/// @notice You can use this contract to open MysteryBox
/// @dev 1 - Common Box, 2 - Uncommon Box, 3 - Rare Box, 4 - Epic Box
contract MysteryBox is
    IMysteryBox,
    ERC1155Upgradeable,
    OwnableUpgradeable,
    ERC1155SupplyUpgradeable,
    ERC2981Upgradeable,
    UUPSUpgradeable
{
    // keccak256(
    //     "EIP712Domain(address verifyingContract)"
    // );
    bytes32 private constant DOMAIN_SEPARATOR_TYPEHASH =
        0x035aff83d86937d35b32e04f0ddc6ff469290eef2f1b692d8a815c89404d4749;

    struct AirdropMint {
        bool isGameAirdrop;
        address user;
        uint256 epoch;
        bool mintDaysRank;
        bool mintTotalRank;
    }

    struct RewardLimit {
        uint256 min;
        uint256 max;
    }

    bool public canOpen = false;
    ERC20 public rewardToken;
    address public operator;
    address public stake;
    address public game;

    mapping(uint256 => RewardLimit) public rewardLimits;
    mapping(address => mapping(uint256 => bool)) public gameEpochMinted;
    mapping(address => mapping(uint256 => bool)) public fiEpochMinted;

    event DepositRewardToken(uint256 id, uint256 amount);
    event WithdrawRewardToken(uint256 amount);
    event Open(address indexed user, uint256 id, uint256 amount);
    event RewardPaid(address user, uint256 id, uint256 reward);
    event SetRewardLimit(uint256 id, uint256 min, uint256 max);

    bytes32 public constant _AIRDROPMINT_TYPEHASH =
        keccak256(
            "AirdropMint(bool isGameAirdrop,address user,uint256 epoch,bool mintDaysRank,bool mintTotalRank)"
        );

    function initialize(ERC20 rewardToken_) public initializer {
        __ERC1155_init("https://sosotribe.com/api/mysteryBox/metadata-{id}");
        __ERC1155Supply_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        rewardToken = rewardToken_;
        transferOwnership(tx.origin);
        _setDefaultRoyalty(tx.origin, 500);
    }

    modifier checkId(uint256 id) {
        require(id >= 1 && id <= 4, "MysteryBox: invalid id");
        _;
    }

    modifier onlyGame() {
        address _owner = owner();
        require(
            msg.sender == _owner || msg.sender == game,
            "MysteryBox: permission denied"
        );
        _;
    }

    function open(uint256 id) external checkId(id) {
        require(canOpen, "MysteryBox: can not open");
        _burn(msg.sender, id, 1);
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        require(rewardBalance > 0, "MysteryBox: rewardBalance is 0");
        require(
            rewardBalance >= rewardLimits[id].max,
            "MysteryBox: rewardBalance is not enough"
        );
        RewardLimit memory limit = rewardLimits[id];
        uint256 r = random(msg.sender, totalSupply(id));
        uint256 amount = (r % limit.max);
        if (amount < limit.min) {
            amount = limit.min;
        }
        _transferReward(id, msg.sender, amount);
        emit Open(msg.sender, id, amount);
    }

    function random(address u, uint256 x) private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, u, x)));
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function contractURI() public pure returns (string memory) {
        return "https://sosotribe.com/api/mysteryBox/contractMetadata";
    }

    /// @dev This event emits when the metadata of a token is changed.
    /// So that the third-party platforms such as NFT market could
    /// timely update the images and related attributes of the NFT.
    event MetadataUpdate(uint256 _tokenId);

    /// @dev This event emits when the metadata of a range of tokens is changed.
    /// So that the third-party platforms such as NFT market could
    /// timely update the images and related attributes of the NFTs.
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    function metadataUpdate(uint256 id) external {
        if (id == 0) {
            emit BatchMetadataUpdate(0, type(uint256).max);
        }
        emit MetadataUpdate(id);
    }

    function setOperator(address _newOp) public onlyOwner {
        operator = _newOp;
    }

    function setStake(address _stake) public onlyOwner {
        stake = _stake;
    }

    function setCanOpen(bool _canOpen) public onlyOwner {
        canOpen = _canOpen;
    }

    function batchSetRewardLimit(
        uint256[] memory ids,
        RewardLimit[] memory _limits
    ) public onlyOwner {
        require(ids.length == _limits.length, "MysteryBox: invalid length");
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            RewardLimit memory _limit = _limits[i];
            rewardLimits[id] = _limit;
            emit SetRewardLimit(id, _limit.min, _limit.max);
        }
    }

    function mint(
        address account,
        uint256 id,
        uint256 amount
    ) public checkId(id) onlyGame {
        _mint(account, id, amount, "");
    }

    function airdropMint(
        AirdropMint memory am,
        bytes memory signature
    ) external {
        bytes32 dataHash = keccak256(abi.encode(_AIRDROPMINT_TYPEHASH, am));
        bytes32 messageHash = _hashTypedData(dataHash);
        address recoved = ECDSA.recover(messageHash, signature);
        if (am.isGameAirdrop) {
            require(
                !gameEpochMinted[am.user][am.epoch],
                "MysteryBox: already minted"
            );
            gameEpochMinted[am.user][am.epoch] = true;
        } else {
            require(
                !fiEpochMinted[am.user][am.epoch],
                "MysteryBox: already minted"
            );
            fiEpochMinted[am.user][am.epoch] = true;
        }
        require(recoved == operator, "MysteryBox: invalid signature");
        require(am.epoch > 0, "MysteryBox: invalid epoch");
        if (am.mintDaysRank) {
            _mint(am.user, 1, 1, "");
        }
        if (am.mintTotalRank) {
            // random mint
            uint256 r = random(am.user, uint256(messageHash));
            // result: 0, 1, 2
            uint256 mintId = (r % 3) + 2;
            // mintId: 1 - Common Box, 2 - Uncommon Box, 3 - Rare Box, 4 - Epic Box
            _mint(am.user, mintId, 1, "");
        }
    }

    function withdrawRewardToken() external onlyOwner {
        uint256 totalRequiredAmount = 0;
        for (uint256 i = 1; i <= 4; i++) {
            uint256 maxReward = rewardLimits[i].max;
            uint256 supply = totalSupply(i);
            totalRequiredAmount += supply * maxReward;
        }
        uint256 currentAmount = rewardToken.balanceOf(address(this));
        if (currentAmount > totalRequiredAmount) {
            uint256 withdrawAmount = currentAmount - totalRequiredAmount;
            rewardToken.transfer(msg.sender, withdrawAmount);
        }
        payable(msg.sender).transfer(address(this).balance);
        emit WithdrawRewardToken(currentAmount);
    }

    function _transferReward(uint256 id, address to, uint256 amount) internal {
        rewardToken.transfer(to, amount);
        emit RewardPaid(to, id, amount);
    }

    function _getDomainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_SEPARATOR_TYPEHASH, address(this)));
    }

    function depositRewardToken(uint256 id, uint256 amount) external {
        rewardToken.transferFrom(msg.sender, address(this), amount);
        emit DepositRewardToken(id, amount);
    }

    /// @notice Creates an EIP-712 typed data hash
    function _hashTypedData(bytes32 dataHash) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked("\x19\x01", _getDomainSeparator(), dataHash)
            );
    }

    // The following functions are overrides required by Solidity.
    function _beforeTokenTransfer(
        address _operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155Upgradeable, ERC1155SupplyUpgradeable) {
        super._beforeTokenTransfer(_operator, from, to, ids, amounts, data);
    }

    function isApprovedForAll(
        address account,
        address _operator
    ) public view override(ERC1155Upgradeable) returns (bool) {
        if (_operator == stake) {
            return true;
        }
        return super.isApprovedForAll(account, operator);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC1155Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

