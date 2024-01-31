// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./ReentrancyGuardUpgradeable.sol";
import "./ECDSA.sol";
import "./Erc721LockRegistry.sol";
import "./DefaultOperatorFiltererUpgradeable.sol";

contract TaijiGenesisV2 is ERC721x, DefaultOperatorFiltererUpgradeable {
    string public baseTokenURI;
    string public tokenURISuffix;
    string public tokenURIOverride;

    uint256 public MAX_SUPPLY;

    uint256 public vitalityRewards;
    bool public canStake;
    mapping(uint256 => bool) public isTokenStake;
    mapping(uint256 => uint256) public tokenStakeTime;
    mapping(address => uint256) public vitalityBalance;

    event Stake(
        uint256 indexed tokenId,
        address indexed by,
        uint256 lastBalance
    );
    event Unstake(
        uint256 indexed tokenId,
        address indexed by,
        uint256 lastBalance
    );
    event Burn(address indexed by, uint256 amount);
    event TransferVitality(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    function initialize(string memory baseURI) public initializer {
        DefaultOperatorFiltererUpgradeable.__DefaultOperatorFilterer_init();
        ERC721x.__ERC721x_init("Taiji Labs Genesis Keys", "TLGK");
        baseTokenURI = baseURI;

        MAX_SUPPLY = 1500;
    }

    function safeMint(address receiver, uint256 quantity) internal {
        require(_totalMinted() + quantity <= MAX_SUPPLY, "exceed MAX_SUPPLY");
        _mint(receiver, quantity);
    }

    // =============== Staking ===============

    function rewardsVitality(uint256 tokenId)
        public
        view
        returns (uint256 _rewards)
    {
        if (isTokenStake[tokenId] == true) {
            return (((block.timestamp - tokenStakeTime[tokenId]) *
                vitalityRewards) / 3600);
        } else {
            return 0;
        }
    }

    function totalBalanceByAddress(address _addr)
        external
        view
        virtual
        returns (uint256 _rewards)
    {
        uint256 _rewardTotal = vitalityBalance[_addr];
        uint256[] memory _tokens = this.tokensOfOwner(_addr);
        for (uint256 i; i < _tokens.length; ++i) {
            _rewardTotal += rewardsVitality(_tokens[i]);
        }
        return _rewardTotal;
    }

    function stake(uint256 tokenId) public {
        require(canStake, "staking not open");
        require(
            msg.sender == ownerOf(tokenId) || msg.sender == owner(),
            "caller must be owner of token or contract owner"
        );
        require(isTokenStake[tokenId] == false, "already staking");
        isTokenStake[tokenId] = true;
        tokenStakeTime[tokenId] = block.timestamp;
        emit Stake(tokenId, msg.sender, vitalityBalance[msg.sender]);
    }

    function unstake(uint256 tokenId) public {
        // require(canStake, "staking not open");
        require(
            msg.sender == ownerOf(tokenId) || msg.sender == owner(),
            "caller must be owner of token or contract owner"
        );
        require(isTokenStake[tokenId] == true, "not staking");
        vitalityBalance[msg.sender] += rewardsVitality(tokenId);
        isTokenStake[tokenId] = false;
        tokenStakeTime[tokenId] = 0;
        emit Unstake(tokenId, msg.sender, vitalityBalance[msg.sender]);
    }

    function burn(uint256 amount) public {
        require(
            balanceOf(msg.sender) > 0 || msg.sender == owner(),
            "caller must be holder of token or contract owner"
        );
        require(vitalityBalance[msg.sender] >= amount, "Not enough balance");
        vitalityBalance[msg.sender] -= amount;
        emit Burn(msg.sender, amount);
    }

    function transferVitalityBalance(address to, uint256 amount) public {
        require(
            balanceOf(msg.sender) > 0 || msg.sender == owner(),
            "caller must be holder of token or contract owner"
        );
        require(vitalityBalance[msg.sender] >= amount, "Not enough balance");
        vitalityBalance[msg.sender] -= amount;
        vitalityBalance[to] += amount;
        emit TransferVitality(msg.sender, to, amount);
    }

    function setTokensStakeStatus(uint256[] memory tokenIds, bool setStake)
        external
    {
        for (uint256 i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (setStake) {
                stake(tokenId);
            } else {
                unstake(tokenId);
            }
        }
    }

    function setVitalityRewards(uint256 _rewards) external onlyOwner {
        vitalityRewards = _rewards;
    }

    function setCanStake(bool _status) external onlyOwner {
        canStake = _status;
    }

    function setVitalityBalance(address to, uint256 amount) external onlyOwner {
        vitalityBalance[to] += amount;
    }

    // =============== Airdrop ===============

    function airdrop(address[] memory receivers) external onlyOwner {
        require(receivers.length >= 1, "at least 1 receiver");
        for (uint256 i; i < receivers.length; i++) {
            address receiver = receivers[i];
            safeMint(receiver, 1);
        }
    }

    function airdropWithAmounts(
        address[] memory receivers,
        uint256[] memory amounts
    ) external onlyOwner {
        require(receivers.length >= 1, "at least 1 receiver");
        for (uint256 i; i < receivers.length; i++) {
            address receiver = receivers[i];
            safeMint(receiver, amounts[i]);
        }
    }

    // =============== URI ===============

    function compareStrings(string memory a, string memory b)
        public
        pure
        returns (bool)
    {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function tokenURI(uint256 _tokenId)
        public
        view
        override(ERC721AUpgradeable, IERC721AUpgradeable)
        returns (string memory)
    {
        if (bytes(tokenURIOverride).length > 0) {
            return tokenURIOverride;
        }
        return string.concat(super.tokenURI(_tokenId), tokenURISuffix);
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        baseTokenURI = baseURI;
    }

    function setTokenURISuffix(string calldata _tokenURISuffix)
        external
        onlyOwner
    {
        if (compareStrings(_tokenURISuffix, "!empty!")) {
            tokenURISuffix = "";
        } else {
            tokenURISuffix = _tokenURISuffix;
        }
    }

    function setTokenURIOverride(string calldata _tokenURIOverride)
        external
        onlyOwner
    {
        if (compareStrings(_tokenURIOverride, "!empty!")) {
            tokenURIOverride = "";
        } else {
            tokenURIOverride = _tokenURIOverride;
        }
    }

    // =============== MARKETPLACE CONTROL ===============

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721x) onlyAllowedOperator(from) {
        require(isTokenStake[tokenId] == false, "Cannot transfer staked token");
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public override(ERC721x) onlyAllowedOperator(from) {
        require(isTokenStake[tokenId] == false, "Cannot transfer staked token");
        super.safeTransferFrom(from, to, tokenId, _data);
    }
}

