//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "./ContractControl.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./MerkleProofUpgradeable.sol";

error TokenIsStaked();

contract NeanderSmol is ContractControl, ERC721EnumerableUpgradeable {
    using StringsUpgradeable for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    uint256 constant TOTAL_SUPPLY = 5678;

    CountersUpgradeable.Counter public _tokenIdTracker;

    string public baseURI;

    uint256 public decimals;
    uint256 public commonSenseMaxLevel;
    mapping(uint256 => uint256) public commonSense;

    bytes32 public merkleRoot;
    mapping(address => bool) private minted;
    mapping(address => uint256) private publicMinted;

    mapping(address => uint256) private multipleMints;
    mapping(address => uint256) private teamAddresses;

    bool public publicActive;
    bool public wlActive;

    uint256 public wlPrice;
    uint256 public publicPrice;

    bool private revealed;

    IERC20 private magic;
    uint256 public magicPrice;
    mapping(address => uint256) private magicMinted;

    bool public treasuryMinted;
    address public treasury;

    event SmolNeanderMint(address to, uint256 tokenId);

    event uriUpdate(string newURI);

    event commonSenseUpdated(uint256 tokenId, uint256 commonSense);

    struct PrimarySkill {
        uint256 mystics;
        uint256 farmers;
        uint256 fighters;
    }

    mapping(uint256 => PrimarySkill) private tokenToSkill;
    mapping(uint256 => bool) public staked;

    event StakeState(uint256 indexed tokenId, bool state);
    event MysticsSkillUpdated(uint256 indexed tokenId, uint256 indexed amount);
    event FarmerSkillUpdated(uint256 indexed tokenId, uint256 indexed amount);
    event FightersSkillUpdated(uint256 indexed tokenId, uint256 indexed amount);

    function initialize() public initializer {
        __ERC721_init("Neander Smol", "NeanderSmol");
        ContractControl.initializeAccess();
        decimals = 9;
        commonSenseMaxLevel = 100 * (10 ** decimals);
        publicActive = false;
        publicPrice = 0.02 ether;
        revealed = true;
        treasuryMinted = false;
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721EnumerableUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return
            ERC721EnumerableUpgradeable.supportsInterface(interfaceId) ||
            AccessControlUpgradeable.supportsInterface(interfaceId);
    }

    function updateCommonSense(
        uint256 _tokenId,
        uint256 amount
    ) external onlyStakingContract {
        if (commonSense[_tokenId] + amount >= commonSenseMaxLevel) {
            commonSense[_tokenId] = commonSenseMaxLevel;
        } else {
            commonSense[_tokenId] += amount;
        }

        emit commonSenseUpdated(_tokenId, commonSense[_tokenId]);
    }

    function developMystics(
        uint256 _tokenId,
        uint256 _amount
    ) external onlyStakingContract {
        tokenToSkill[_tokenId].mystics += _amount;
        emit MysticsSkillUpdated(_tokenId, _amount);
    }

    function developFarmers(
        uint256 _tokenId,
        uint256 _amount
    ) external onlyStakingContract {
        tokenToSkill[_tokenId].farmers += _amount;
        emit FarmerSkillUpdated(_tokenId, _amount);
    }

    function developFighter(
        uint256 _tokenId,
        uint256 _amount
    ) external onlyStakingContract {
        tokenToSkill[_tokenId].fighters += _amount;
        emit FightersSkillUpdated(_tokenId, _amount);
    }

    function stakingHandler(
        uint256 _tokenId,
        bool _state
    ) external onlyStakingContract {
        staked[_tokenId] = _state;
        emit StakeState(_tokenId, _state);
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _firstTokenId,
        uint256 _batchSize
    ) internal virtual override {
        if (staked[_firstTokenId]) revert TokenIsStaked();
        super._beforeTokenTransfer(_from, _to, _firstTokenId, _batchSize);
    }

    function getCommonSense(uint256 _tokenId) external view returns (uint256) {
        return commonSense[_tokenId] / (10 ** decimals);
    }

    function getPrimarySkill(
        uint256 _tokenId
    ) external view returns (PrimarySkill memory) {
        return tokenToSkill[_tokenId];
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function flipPublicState() external onlyAdmin {
        publicActive = !publicActive;
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString()))
                : "";
    }

    function withdrawAll() external onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
        require(magic.transfer(msg.sender, magic.balanceOf(address(this))));
    }

    function setTreasury(address _treasury) external onlyAdmin {
        treasury = _treasury;
    }
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

