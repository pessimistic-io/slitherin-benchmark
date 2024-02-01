// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./IERC721Enumerable.sol";
import "./IERC721Receiver.sol";
import "./EnumerableSet.sol";
import "./ReentrancyGuard.sol";
import "./Math.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./GlobalClaimer.sol";

contract JingleDogeStaking is
    GlobalClaimer,
    Ownable,
    IERC721Receiver,
    ReentrancyGuard,
    Pausable
{
    using EnumerableSet for EnumerableSet.UintSet;

    address public jingleDogeAddress;
    address public erc20Address;

    address public globalDistributer;

    // expiration time of reward providing
    uint256 public expiration;

    //rates governs how often you receive your token
    uint256 rate;

    // mappings
    mapping(address => EnumerableSet.UintSet) private _deposits;

    mapping(address => mapping(uint256 => uint256)) public _depositTime;

    mapping(uint256 => uint256) public tokenPoints;

    mapping(address => uint256) public rewardCollected;

    constructor(
        address _jingleDogeAddress,
        uint256 _expiration,
        address _erc20Address
    ) {
        jingleDogeAddress = _jingleDogeAddress;
        expiration = _expiration;
        erc20Address = _erc20Address;
        _pause();
    }

    function changeJingleDogeAddress(address _jingleDogeAddress)
        public
        onlyOwner
    {
        jingleDogeAddress = _jingleDogeAddress;
    }

    function changeRewardTokenAddress(address rewardAddress) public onlyOwner {
        erc20Address = rewardAddress;
    }

    function changeGlobalDistributer(address _globalDistributer)
        public
        onlyOwner
    {
        globalDistributer = _globalDistributer;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setRate(uint256 _rate) public onlyOwner {
        rate = _rate;
    }

    function setExpiration(uint256 _expiration) public onlyOwner {
        expiration = _expiration;
    }

    //check deposit amount.
    function depositsOf(address account)
        public
        view
        override
        returns (uint256[] memory)
    {
        EnumerableSet.UintSet storage depositSet = _deposits[account];
        uint256[] memory tokenIds = new uint256[](depositSet.length());

        for (uint256 i; i < depositSet.length(); i++) {
            tokenIds[i] = depositSet.at(i);
        }

        return tokenIds;
    }

    function calculateRewards(address account, uint256[] memory tokenIds)
        public
        view
        override
        returns (uint256[] memory rewards)
    {
        rewards = new uint256[](tokenIds.length);

        for (uint256 i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            rewards[i] =
                rate *
                (_deposits[account].contains(tokenId) ? 1 : 0) *
                (Math.min(block.timestamp, expiration) -
                    _depositTime[account][tokenId]);
        }

        return rewards;
    }

    //reward amount by address/tokenIds[]
    function calculateReward(address account, uint256 tokenId)
        public
        view
        returns (uint256)
    {
        require(
            Math.min(block.timestamp, expiration) >
                _depositTime[account][tokenId],
            "Invalid TimeStamp"
        );
        return
            rate *
            (_deposits[account].contains(tokenId) ? 1 : 0) *
            (Math.min(block.timestamp, expiration) -
                _depositTime[account][tokenId]);
    }

    //reward claim function
    function claimRewards(uint256[] calldata tokenIds) public whenNotPaused {
        uint256 reward;

        for (uint256 i; i < tokenIds.length; i++) {
            require(
                _deposits[msg.sender].contains(tokenIds[i]),
                "Staking: token not deposited"
            );
            reward += calculateReward(msg.sender, tokenIds[i]);
            _depositTime[msg.sender][tokenIds[i]] = block.timestamp;
        }

        if (reward > 0) {
            rewardCollected[msg.sender] += reward;
            IERC20(erc20Address).transfer(msg.sender, reward);
        }
    }

    function deposit(uint256[] calldata tokenIds) external whenNotPaused {
        require(msg.sender != jingleDogeAddress, "Invalid address");

        for (uint256 i; i < tokenIds.length; i++) {
            IERC721(jingleDogeAddress).safeTransferFrom(
                msg.sender,
                address(this),
                tokenIds[i],
                ""
            );
            _depositTime[msg.sender][tokenIds[i]] = block.timestamp;
            _deposits[msg.sender].add(tokenIds[i]);
        }
    }

    //withdrawal function.
    function withdraw(uint256[] calldata tokenIds)
        external
        whenNotPaused
        nonReentrant
    {
        claimRewards(tokenIds);

        for (uint256 i; i < tokenIds.length; i++) {
            require(
                _deposits[msg.sender].contains(tokenIds[i]),
                "Staking: token not deposited"
            );

            _deposits[msg.sender].remove(tokenIds[i]);

            IERC721(jingleDogeAddress).safeTransferFrom(
                address(this),
                msg.sender,
                tokenIds[i],
                ""
            );
        }
    }

    function withdrawTokens() external onlyOwner {
        uint256 tokenSupply = IERC20(erc20Address).balanceOf(address(this));
        IERC20(erc20Address).transfer(msg.sender, tokenSupply);
    }

    function claimAll(
        address tokenOwner,
        uint256[] memory tokenIds,
        uint256 amount
    ) external override {
        require(msg.sender == globalDistributer);

        for (uint256 i; i < tokenIds.length; i++) {
            _depositTime[tokenOwner][tokenIds[i]] = block.timestamp;
        }

        if (amount > 0) {
            rewardCollected[tokenOwner] += amount;
            IERC20(erc20Address).transfer(tokenOwner, amount);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

