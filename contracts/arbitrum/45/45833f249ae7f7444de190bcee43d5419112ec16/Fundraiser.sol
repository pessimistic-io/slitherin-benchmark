// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IERC20.sol";
import "./IERC721.sol";
import "./Pausable.sol";
import "./SafeMath.sol";
import "./MerkleProof.sol";
import "./Ownable.sol";
import "./FundraiserFactory.sol";
import "./Vesting.sol";
import "./VestingCliff.sol";

contract Fundraiser is Pausable, Ownable {
    using SafeMath for uint256;
    struct TokenConfig {
        address depositToken1;
        address depositToken2;
        address factory;
    }

    struct AllocationConfig {
        uint256 nftTicketAllocation;
        uint256 baseAllocationPerWallet;
        uint256 maxTotalAllocation;
        uint256 rate;
    }

    struct TimeConfig {
        uint256 nftStartTime;
        uint256 openStartTime;
        uint256 endTime;
    }

    TokenConfig public tokenConfig;
    AllocationConfig public allocationConfig;
    TimeConfig public timeConfig;
    address public nftToken;
    bytes32 internal merkleRoot;
    uint256 public whitelistedAllocation;
    uint256 public constant ALLOCATION_DIVIDER = 10000;


    mapping(address => uint256) public depositedAmount;
    uint256 public totalDeposited;
    mapping(uint256 => bool) public usedNftId;
    address public vestingAddress;

    mapping(address => bool) public whitelistUser;

    event Deposit(address indexed user, uint256 amount);
    event DepositWithNft(address indexed user, uint256 amount, uint256[] nftIds);
    event DepositWithWhitelist(address indexed user, uint256 amount);
    event DepositWithNftAndWhitelist(address indexed user, uint256 amount, uint256[] nftIds);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event VestingDeployed(address vestingAddress);
    event RegisterWhitelist(bytes32 merkleRoot, uint256 whitelistedAllocation);
    event WithdrawToken(address user, uint256 amount);
    event WithdrawEth(address user, uint256 amount);

    modifier canDeposit(uint256 _amount) {
        require(_amount > 0, "Fundraiser: deposit amount must be greater than 0");
        require(block.timestamp <= timeConfig.endTime, "Fundraising has already ended");
        require(totalDeposited.add(_amount) <= allocationConfig.maxTotalAllocation, "Max total allocation reached");
        _;
    }

    error TransferFailed();

    constructor(
        address _depositToken1,
        address _depositToken2,
        uint256 _baseAllocationPerWallet,
        uint256 _maxTotalAllocation,
        uint256 _nftTicketAllocation,
        uint256 _rate,
        uint256 _nftFundraiseStartTime,
        uint256 _openFundraiseStartTime,
        uint256 _fundraiseEndTime,
        address _owner,
        address _factory,
        address _nftToken
    ) {
        require(_nftFundraiseStartTime <= _openFundraiseStartTime, "NFT fundraise start time must be greater than open fundraise start time");
        require(_openFundraiseStartTime <= _fundraiseEndTime, "Open fundraise start time must not be greater than fundraise end time");
        require(_baseAllocationPerWallet <= _maxTotalAllocation, "Base allocation per wallet must not exceed maximum total allocation");

        tokenConfig.depositToken1 = _depositToken1;
        tokenConfig.depositToken2 = _depositToken2;
        allocationConfig.baseAllocationPerWallet = _baseAllocationPerWallet;
        allocationConfig.maxTotalAllocation = _maxTotalAllocation;
        allocationConfig.nftTicketAllocation = _nftTicketAllocation;
        allocationConfig.rate = _rate;
        timeConfig.nftStartTime = _nftFundraiseStartTime;
        timeConfig.openStartTime = _openFundraiseStartTime;
        timeConfig.endTime = _fundraiseEndTime;
        tokenConfig.factory = _factory;
        nftToken = _nftToken;
        _transferOwnership(_owner);
    }

    function deposit(uint256 _token1Amount, uint256 _token2Amount) external whenNotPaused canDeposit(_token1Amount + _token2Amount) {
        require(block.timestamp >= timeConfig.openStartTime, "Fundraising has not started yet");
        uint256 userNewDeposit = _token1Amount + _token2Amount;
        require(depositedAmount[msg.sender] + userNewDeposit <= allocationConfig.baseAllocationPerWallet, "Max allocation per wallet reached");

        chargeUser(_token1Amount, _token2Amount);

        depositedAmount[msg.sender] = depositedAmount[msg.sender].add(userNewDeposit);
        totalDeposited = totalDeposited.add(userNewDeposit);

        emit Deposit(msg.sender, _token1Amount + _token2Amount);
    }

    function depositWithNft(uint256 _token1Amount, uint256 _token2Amount, uint256[] memory nftIds) external whenNotPaused canDeposit(_token1Amount + _token2Amount) {
        require(block.timestamp >= timeConfig.nftStartTime, "Fundraising has not started yet");
        require(block.timestamp < timeConfig.openStartTime, "Fundraising in open phase");
        require(nftIds.length <= 3, "Max nftIds is 3");
        require(nftIds.length >= 1, "Min nftIds is 1");
        require(areElementsUnique(nftIds), "NFT identifiers must be unique!");
        uint256 userDeposit = _token1Amount + _token2Amount;

        useAllocationWithNfts(nftIds, userDeposit);
        chargeUser(_token1Amount, _token2Amount);

        depositedAmount[msg.sender] = depositedAmount[msg.sender].add(userDeposit);
        totalDeposited = totalDeposited.add(userDeposit);

        emit DepositWithNft(msg.sender, userDeposit, nftIds);
    }

    function depositWithWhitelist(uint256 _token1Amount, uint256 _token2Amount, bytes32[] memory proof_) external whenNotPaused canDeposit(_token1Amount + _token2Amount) {
        require(block.timestamp >= timeConfig.nftStartTime, "Fundraising has not started yet");
        require(block.timestamp < timeConfig.openStartTime, "Fundraising in open phase");
        require(MerkleProof.verify(proof_, merkleRoot, keccak256(abi.encodePacked(msg.sender))), "User is not whitelisted.");
        whitelistUser[msg.sender] = true;

        uint256 userDeposit = depositedAmount[msg.sender];
        uint256 userNewDeposit = _token1Amount + _token2Amount;

        require(userNewDeposit.add(userDeposit) <= whitelistedAllocation, "Whitelist max allocation overflow");
        chargeUser(_token1Amount, _token2Amount);

        depositedAmount[msg.sender] = depositedAmount[msg.sender].add(userNewDeposit);
        totalDeposited = totalDeposited.add(userNewDeposit);

        emit DepositWithWhitelist(msg.sender, userNewDeposit);
    }

    function depositWithWhitelistAndNft(uint256 _token1Amount, uint256 _token2Amount, uint256[] memory nftIds, bytes32[] memory proof_) external whenNotPaused canDeposit(_token1Amount + _token2Amount) {
        require(block.timestamp >= timeConfig.nftStartTime, "Fundraising has not started yet");
        require(block.timestamp < timeConfig.openStartTime, "Fundraising in open phase");
        require(nftIds.length <= 3, "Max nftIds is 3");
        require(nftIds.length >= 1, "Min nftIds is 1");
        require(areElementsUnique(nftIds), "NFT identifiers must be unique!");

        require(MerkleProof.verify(proof_, merkleRoot, keccak256(abi.encodePacked(msg.sender))), "User is not whitelisted.");
        whitelistUser[msg.sender] = true;

        uint256 userDeposit = depositedAmount[msg.sender];

        (uint256 validNftCount, uint256 invalidNftCount) = countValidAndInvalidNfts(msg.sender, nftIds);
        uint256 nftMaxAllocation = calculateMaxAllocation(userDeposit, validNftCount, invalidNftCount);

        uint256 userNewDeposit = _token1Amount + _token2Amount;
        require(userDeposit.add(userNewDeposit) <= nftMaxAllocation.add(whitelistedAllocation), "Max whitelisted and nft allocation overflow");

        for (uint256 i = 0; i < nftIds.length; i++) {
            uint256 nftId = nftIds[i];

            if (IERC721(nftToken).ownerOf(nftId) == msg.sender && !usedNftId[nftId]) {
                usedNftId[nftId] = true;
            }
        }

        chargeUser(_token1Amount, _token2Amount);

        depositedAmount[msg.sender] = depositedAmount[msg.sender].add(userNewDeposit);
        totalDeposited = totalDeposited.add(userNewDeposit);

        emit DepositWithNftAndWhitelist(msg.sender, userNewDeposit, nftIds);
    }

    function setWhitelist(bytes32 _merkleRoot, uint256 _whitelistedAllocation) external onlyOwner {

        whitelistedAllocation = _whitelistedAllocation;
        merkleRoot = _merkleRoot;
        emit RegisterWhitelist(_merkleRoot, _whitelistedAllocation);
    }

    function withdraw() external whenNotPaused onlyOwner {
        require(block.timestamp > timeConfig.endTime, "Fundraise has not ended yet");

        uint256 balance1 = IERC20(tokenConfig.depositToken1).balanceOf(address(this));
        if (
            !IERC20(tokenConfig.depositToken1).transfer(owner(), balance1)
        ) {
            revert TransferFailed();
        }

        uint256 balance2 = IERC20(tokenConfig.depositToken2).balanceOf(address(this));
        if (
            !IERC20(tokenConfig.depositToken2).transfer(owner(), balance2)
        ) {
            revert TransferFailed();
        }


        FundraiserFactory(tokenConfig.factory).endFundraiser(address(this));

        emit Withdraw(owner(), balance1 + balance2);
    }

    function startVesting(uint256 _vestingStart, uint256 _vestingEnd, address _tokenAddress, uint256 _tokenAmount, uint256 _ethFee) external whenNotPaused onlyOwner {

        require(vestingAddress == address(0), "Vesting already deployed");
        require(_vestingStart > timeConfig.endTime, "Vesting has to start after fundraise end time");

        Vesting vesting = new Vesting(
            address(this),
            _vestingStart,
            _vestingEnd,
            _tokenAddress,
            _ethFee,
            owner()
        );

        vestingAddress = address(vesting);

        if (
            !IERC20(_tokenAddress).transferFrom(msg.sender, vestingAddress, _tokenAmount)
        ) {
            revert TransferFailed();
        }

        emit VestingDeployed(vestingAddress);
    }

    function startVestingCliff(
        uint256 _vestingStart,
        uint256 _vestingEnd,
        address _tokenAddress,
        uint256 _tokenAmount,
        uint256 _tgeDate,
        uint256 _tgePercent,
        uint256 _ethFee
    ) external whenNotPaused onlyOwner {

        require(vestingAddress == address(0), "Vesting already deployed");
        require(_vestingStart > timeConfig.endTime, "Vesting has to start after fundraise end time");

        VestingCliff vesting = new VestingCliff(
            address(this),
            _vestingStart,
            _vestingEnd,
            _tokenAddress,
            _tgePercent,
            _tgeDate,
            _ethFee,
            owner()
        );

        vestingAddress = address(vesting);

        if (
            !IERC20(_tokenAddress).transferFrom(msg.sender, vestingAddress, _tokenAmount)
        ) {
            revert TransferFailed();
        }

        emit VestingDeployed(vestingAddress);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function userAllocation(address userAddress) external view returns (uint256) {
        return depositedAmount[userAddress].mul(allocationConfig.rate).div(ALLOCATION_DIVIDER);
    }

    function getEndTime() external view returns (uint256) {
        return timeConfig.endTime;
    }

    function getMaxAllocation(address userAddress, uint256[] memory nftIds) external view returns (uint256) {
        uint256 userDeposit = depositedAmount[userAddress];
        (uint256 validNftCount, uint256 invalidNftCount) = countValidAndInvalidNfts(userAddress, nftIds);
        uint256 userMaxAllocation = calculateMaxAllocation(userDeposit, validNftCount, invalidNftCount);

        uint256 currentTotal = totalDeposited.add(userMaxAllocation);
        if (currentTotal > allocationConfig.maxTotalAllocation) {
            return allocationConfig.maxTotalAllocation.sub(totalDeposited);
        }

        return userMaxAllocation;
    }

    function useAllocationWithNfts(uint256[] memory nftIds, uint256 additionalDeposit) private {
        uint256 userDeposit = depositedAmount[msg.sender];
        (uint256 validNftCount, uint256 invalidNftCount) = countValidAndInvalidNfts(msg.sender, nftIds);
        uint256 maxAllocation = calculateMaxAllocation(userDeposit, validNftCount, invalidNftCount);

        require(userDeposit.add(additionalDeposit) <= maxAllocation, "Max allocation overflow");

        for (uint256 i = 0; i < nftIds.length; i++) {
            uint256 nftId = nftIds[i];
            address tempOwner = IERC721(nftToken).ownerOf(nftId);
            require(tempOwner == msg.sender, "You are not the nft owner");
            usedNftId[nftId] = true;
        }
    }

    function countValidAndInvalidNfts(address userAddress, uint256[] memory nftIds) private view returns (uint256 validNftCount, uint256 invalidNftCount) {

        for (uint256 i = 0; i < nftIds.length; i++) {
            uint256 nftId = nftIds[i];

            if (IERC721(nftToken).ownerOf(nftId) == userAddress) {
                if (!usedNftId[nftId]) {
                    validNftCount++;
                } else {
                    invalidNftCount++;
                }
            }
        }
    }

    function calculateMaxAllocation(uint256 userDeposit, uint256 validNftCount, uint256 invalidNftCount) private view returns (uint256) {
        uint256 maxAllocation;
        uint256 allowedNfts;

        uint256 userAllo;
        if (whitelistUser[msg.sender]) {
            userAllo = whitelistedAllocation;
        }

        if (userDeposit <= userAllo) {
            maxAllocation = userAllo.add(validNftCount.mul(allocationConfig.nftTicketAllocation));
        } else {
            uint256 threshold1 = userAllo.add(allocationConfig.nftTicketAllocation);
            uint256 threshold2 = userAllo.add(allocationConfig.nftTicketAllocation.mul(2));

            if (userDeposit <= threshold1) {
                allowedNfts = invalidNftCount >= 1 ? 1 + validNftCount : validNftCount;
            } else if (userDeposit <= threshold2) {
                allowedNfts = invalidNftCount >= 2 ? 2 + validNftCount : invalidNftCount == 1 ? validNftCount + 1 : validNftCount;
            } else {
                allowedNfts = invalidNftCount >= 3 ? 3 : validNftCount + invalidNftCount;
            }
            maxAllocation = userAllo.add(allowedNfts.mul(allocationConfig.nftTicketAllocation));
        }

        return maxAllocation;
    }

    function checkUsed(uint256[] memory nftIds) external view returns (uint256[] memory) {
        uint256[] memory validNfts = new uint256[](nftIds.length);

        uint256 validCount = 0;
        for (uint256 i = 0; i < nftIds.length; i++) {
            uint256 nftId = nftIds[i];
            if (!usedNftId[nftId]) {
                validNfts[validCount] = nftId;
                validCount++;
            }
        }

        uint256[] memory result = new uint256[](validCount);
        for (uint256 i = 0; i < validCount; i++) {
            result[i] = validNfts[i];
        }

        return result;
    }

    function areElementsUnique(uint256[] memory nftIds) internal pure returns (bool) {
        if (nftIds.length > 1 && nftIds[0] == nftIds[1]) return false;
        if (nftIds.length > 2 && (nftIds[0] == nftIds[2] || nftIds[1] == nftIds[2])) return false;
        return true;
    }

    function chargeUser(uint256 _token1Amount, uint256 _token2Amount) internal {
        if (_token1Amount > 0) {
            if (!IERC20(tokenConfig.depositToken1).transferFrom(msg.sender, address(this), _token1Amount)) {
                revert TransferFailed();
            }
        }

        if (_token2Amount > 0) {
            if (!IERC20(tokenConfig.depositToken2).transferFrom(msg.sender, address(this), _token2Amount)) {
                revert TransferFailed();
            }
        }
    }

    function withdrawToken(IERC20 token, uint256 amount) external onlyOwner {

        if (
            !token.transfer(owner(), amount)
        ) {
            revert TransferFailed();
        }

        emit WithdrawToken(owner(), amount);
    }

    function withdrawEth(uint256 amount) external onlyOwner {

        (bool success,) = payable(owner()).call{value : amount}("");
        if (!success) {
            revert TransferFailed();
        }
        emit WithdrawEth(owner(), amount);
    }
}



