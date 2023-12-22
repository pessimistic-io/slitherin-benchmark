// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.9.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ERC721A.sol";

contract AI_APE_IDO is Ownable, ReentrancyGuard {
    uint256 public investmentTokenDecimals;
    address public defaultInvestmentToken;
    uint256 public idoStartTime = block.timestamp + 10;
    uint256 public idoEndTime = block.timestamp + 3600 * 24 * 7;
    uint256 public airdropAmount =
        3000000000000 * 10 ** investmentTokenDecimals;
    uint256 public airdropRecord = 60000000000 * 10 ** investmentTokenDecimals;
    uint256 public airdropNftAmount =
        1869000000000 * 10 ** investmentTokenDecimals;
    address[] public airdropAddress;
    uint256 public maxQualifiedAddresses = 50000;
    address public nftAddress;
    mapping(address => address) public referrers;
    mapping(address => address[]) public inviteRecords;
    mapping(address => uint256[2]) public inviteNumRecords;
    mapping(address => uint256) public referralRewards;
    mapping(address => uint256) public referrersRewards;
    mapping(address => uint256) public airdropRecords;
    mapping(address => uint256[]) public nftOwenMap;
    mapping(address => uint256) public nftReceivedTimes;

    event Received(address indexed investor, uint256 amount);
    event Rewards(address indexed investor, uint256 amount);
    event AirdropReferral(
        address indexed referrer,
        address indexed investor,
        uint256 reward
    );

    constructor(
        address _allowedinvestmentTokens,
        uint256 _investmentTokenDecimals,
        address _nft
    ) {
        investmentTokenDecimals = _investmentTokenDecimals;
        defaultInvestmentToken = _allowedinvestmentTokens;
        nftAddress = _nft;
    }

    function launch(
        uint256 _idoStartTime,
        uint256 _idoEndTime,
        address _defaultInvestmentToken,
        uint256 _investmentTokenDecimals,
        address _nftAddress
    ) public onlyOwner {
        idoStartTime = _idoStartTime;
        idoEndTime = _idoEndTime;
        defaultInvestmentToken = _defaultInvestmentToken;
        investmentTokenDecimals = _investmentTokenDecimals;
        nftAddress = _nftAddress;
    }

    /**
     * @dev 获取myAddress的被邀请人地址
     */
    function getChilds(
        address myAddress
    ) external view returns (address[] memory childs) {
        childs = inviteRecords[myAddress];
    }

    /**
     * @dev 获取myAddress的被邀请人数量
     */
    function getInviteNum(
        address myAddress
    ) external view returns (uint256[2] memory) {
        return inviteNumRecords[myAddress];
    }

    /**
     * @dev 领取邀请奖励
     */
    function claimReferralRewards() external nonReentrant {
        uint256 token = referralRewards[msg.sender];
        require(token > 0, "reward is zero");
        require(
            IERC20(defaultInvestmentToken).transfer(msg.sender, token),
            "Transfer failed"
        );
        emit Rewards(msg.sender, token);
    }

    function withdrawTokens() external onlyOwner {
        require(block.timestamp > idoEndTime, "IDO not ended");
        require(
            IERC20(defaultInvestmentToken).transfer(
                owner(),
                IERC20(defaultInvestmentToken).balanceOf(address(this))
            ),
            "Transfer failed"
        );
    }

    function isQualified() public view returns (bool) {
        return msg.sender.balance > 0 && airdropRecords[msg.sender] == 0;
    }

    function getAirdrop(address referrer) external nonReentrant {
        require(
            block.timestamp >= idoStartTime && block.timestamp <= idoEndTime,
            "airdrop not active"
        );
        require(isQualified(), "You have already received it.");
        require(
            maxQualifiedAddresses > 0,
            "Maximum qualified addresses reached"
        );
        require(msg.sender.balance > 0, "not qualified");
        uint256 airdropAmountOne = airdropAmount;
        if ((referrer != address(0) && referrer != msg.sender)) {
            if (referrers[msg.sender] != address(0)) {
                referrer = referrers[msg.sender];
                referrersRewards[msg.sender] += airdropRecord;
            } else {
                inviteRecords[referrer].push(msg.sender);
                referrersRewards[msg.sender] = airdropRecord;
            }
            referrers[msg.sender] = referrer;
            inviteNumRecords[referrer][0]++;
            referralRewards[referrer] += airdropRecord;
            airdropAmountOne += airdropRecord;
            emit AirdropReferral(referrer, msg.sender, airdropRecord);
        }

        require(
            IERC20(defaultInvestmentToken).transfer(
                msg.sender,
                airdropAmountOne
            ),
            "Transfer failed"
        );
        airdropRecords[msg.sender] = airdropAmountOne;
        airdropAddress.push(msg.sender);
        maxQualifiedAddresses -= 1;
    }

    function getAllNft(
        address myAddress
    ) public view returns (uint256[] memory nftAll) {
        uint256[] memory nftAllItem = nftOwenMap[msg.sender];
        ERC721A nft = ERC721A(nftAddress);
        uint256 nftAmount = nft.totalSupply();
        for (uint256 i = 0; i < nftAmount; i++) {
            address nftOwner = nft.ownerOf(i);
            if (nftOwner == myAddress) {
                nftAllItem[i] = i;
            }
        }
        return (nftAllItem);
    }

    function getNftOwner(uint256 i) public view returns (address) {
        return ERC721A(nftAddress).ownerOf(i);
    }

    function getNftTotalSupply() public view returns (uint256) {
        return ERC721A(nftAddress).totalSupply();
    }

    function getAirdropByNft() external nonReentrant {
        uint256[] memory nftAll = getAllNft(msg.sender);
        require(nftAll.length > 0, "You don't have NFT");
        uint256[] storage nftOwenList = nftOwenMap[msg.sender];
        uint256 airdropCountBefore = nftReceivedTimes[msg.sender];
        uint256 airdropCount = 0;
        require(airdropCountBefore < 10, "No more than 10");
        for (uint256 i = 0; i < nftAll.length; i++) {
            uint256 tokenId = nftAll[i];
            bool isOwned = false;
            for (uint256 j = 0; j < nftOwenList.length; j++) {
                if (tokenId == nftOwenList[j]) {
                    isOwned = true;
                    break;
                }
            }
            if (!isOwned) {
                airdropCount++;
                nftOwenList.push(tokenId);
            }
            if (airdropCount + airdropCountBefore >= 10) {
                break;
            }
        }
        require(airdropCount > 0, "You have already received it.");
        nftOwenMap[msg.sender] = nftOwenList;
        nftReceivedTimes[msg.sender] = airdropCount;
        require(
            IERC20(defaultInvestmentToken).transfer(
                msg.sender,
                airdropNftAmount
            ),
            "Transfer failed"
        );
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}

