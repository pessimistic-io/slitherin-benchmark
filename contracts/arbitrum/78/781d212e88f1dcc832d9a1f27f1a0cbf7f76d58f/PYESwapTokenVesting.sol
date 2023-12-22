// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Ownable } from "./Ownable.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { IPYESwapToken } from "./IPYESwapToken.sol";

contract PYESwapTokenVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    mapping(address => uint256) public allotments;
    mapping(address => uint256) public withdrawn;
    mapping(address => uint256) public claimedWETH;
    mapping(address => uint256) public excludedWETH;

    address public immutable pyes;
    address public immutable weth;


    uint256 public startTime; // beginning of 180 day vesting window (unix timestamp)
    uint256 public endTime; // end of 180 day vesting window (unix timestamp)
    uint256 public immutable totalAllotments; // Total $PYES tokens vested
    uint256 public totalWithdrawn;
    uint256 public currentVested;
    int256 private allocated;
    bool private allotmentsSet;

    uint256 public totalRewardsWETH;
    uint256 public totalDistributedWETH;
    uint256 public rewardsPerShareWETH;

    string public CONTRACT_DESCRIPTION;
    uint256 private constant A_FACTOR = 10**18;
    uint256 public constant PERIOD_DIVISOR = 5555555555555556;
    
    event TokensClaimed(address indexed account, uint256 amountPYES, uint256 amountWETH);
    event AccountUpdated(address oldAccount, address newAccount, uint256 allotted, uint256 withdrawn);
    event DeployedWithArgs(bytes abiParams);
   
    constructor(
        address _vestAdmin, 
        address _weth, 
        address _pyes, 
        uint256 _startTime, 
        uint256 _totalVested, 
        string memory _description
    ) {
        _transferOwnership(_vestAdmin);
        startTime = _startTime; 
        endTime = _startTime + 180 days;
        totalAllotments = _totalVested;
        CONTRACT_DESCRIPTION = _description;
        weth = _weth;
        pyes = _pyes;

        bytes memory abiParams = abi.encodePacked(
            _vestAdmin,
            _weth,
            _pyes, 
            _startTime, 
            _totalVested, 
            _description
        );
        emit DeployedWithArgs(abiParams);
    }

    function setAllotments(
        address[] calldata _accounts, 
        uint32[] calldata _percentShare,
        bool finalize
    ) external onlyOwner returns (int256 _allocated, int256 variance) {
        require(!allotmentsSet, "Allotments already set");
        require(_accounts.length == _percentShare.length, "Array length mismatch");
        uint256 s;
        for (uint256 i = 0; i < _accounts.length; i++) {
            require(allotments[_accounts[i]] == 0, "Duplicate account");
            s = (totalAllotments * _percentShare[i]) / 100000000;
            allotments[_accounts[i]] = s;
            _allocated += int256(s);
        }
        allocated += _allocated;
        if (finalize) {
            variance = int256(totalAllotments) - allocated;
            require(variance < 0 ? variance > -1 ether : variance < 1 ether, "Incorrect amounts allotted");
            allotmentsSet = true;
            currentVested = totalAllotments;
        }
    }

    function updateStartTime(uint256 _newStartTime) external onlyOwner {
        require(startTime > block.timestamp, "Already started");
        require(_newStartTime > block.timestamp, "Must start in future");
        startTime = _newStartTime;
        endTime = _newStartTime + 180 days;
    }

    function updateAccountAddress(address _oldAccount, address _newAccount) external {
        require(msg.sender == _oldAccount, "Only callable by _oldAccount");
        require(allotments[_oldAccount] > 0, "_oldAccount has no allotments");
        require(allotments[_newAccount] == 0, "_newAccount already allotted");
        allotments[_newAccount] = allotments[_oldAccount];
        withdrawn[_newAccount] = withdrawn[_oldAccount];
        delete allotments[_oldAccount];
        delete withdrawn[_oldAccount];

        emit AccountUpdated(_oldAccount, _newAccount, allotments[_newAccount], withdrawn[_newAccount]);
    }

    function recoverAccount(address _oldAccount, address _newAccount) external onlyOwner {
        require(allotments[_oldAccount] > 0, "_oldAccount has no allotments");
        require(allotments[_newAccount] == 0, "_newAccount already allotted");
        allotments[_newAccount] = allotments[_oldAccount];
        withdrawn[_newAccount] = withdrawn[_oldAccount];
        delete allotments[_oldAccount];
        delete withdrawn[_oldAccount];

        emit AccountUpdated(_oldAccount, _newAccount, allotments[_newAccount], withdrawn[_newAccount]);
    }

    function claimTokens() external nonReentrant {
        (uint256 withdrawablePYES, uint256 withdrawableWETH) = _calculateWithdrawableAmounts(msg.sender);
        require(withdrawablePYES > 0 || withdrawableWETH > 0, "Nothing to claim right now"); 

        if (withdrawablePYES > 0) {   
            IPYESwapToken(pyes).mintVestedTokens(withdrawablePYES, msg.sender);
            withdrawn[msg.sender] += withdrawablePYES;
            totalWithdrawn += withdrawablePYES;
            currentVested -= withdrawablePYES;
        }

        if (withdrawableWETH > 0) {
            IERC20(weth).safeTransfer(msg.sender, withdrawableWETH);
            claimedWETH[msg.sender] += withdrawableWETH;
            excludedWETH[msg.sender] = getCumulativeRewardsWETH(allotments[msg.sender] - withdrawn[msg.sender]);
            totalDistributedWETH += withdrawableWETH;
        }

        emit TokensClaimed(msg.sender, withdrawablePYES, withdrawableWETH);
    }

    function addWETHDonation(uint256 _amount) external nonReentrant {
        IERC20(weth).safeTransferFrom(msg.sender, address(this), _amount);
        totalRewardsWETH += _amount;
        rewardsPerShareWETH += (A_FACTOR * _amount) / currentVested;
    }

    function calculateWithdrawableAmounts(
        address _account
    ) external view returns (
        uint256 withdrawablePYES, 
        uint256 withdrawableWETH
    ) {
        return _calculateWithdrawableAmounts(_account);
    }

    function getCumulativeRewardsWETH(uint256 balance) internal view returns (uint256) {
        return (balance * rewardsPerShareWETH) / A_FACTOR;
    }

    function _calculateWithdrawableAmounts(
        address _address
    ) internal view returns (
        uint256 withdrawablePYES, 
        uint256 withdrawableWETH
    ) {
        uint256 original = allotments[_address]; // initial allotment
        uint256 claimed = withdrawn[_address]; // amount user has claimed
        uint256 available = original - claimed; // amount left that can be claimed

        if (block.timestamp > startTime) { 
            uint256 periodAmount = (original * PERIOD_DIVISOR) / A_FACTOR; // 1/60th of user's original allotment;
            uint256 vestedTime = (getElapsedTime() / 1 days) + 1;
            uint256 unlocked = periodAmount * vestedTime;
            uint256 unclaimed = unlocked - claimed;
            withdrawablePYES = unclaimed < available ? unclaimed : available; 
        }

        if (available > 0) {
            uint256 totalWETHReward = getCumulativeRewardsWETH(available);
            uint256 totalWETHExcluded = excludedWETH[_address];
            if (totalWETHReward <= totalWETHExcluded) {
                withdrawableWETH = 0; 
            }
            withdrawableWETH = totalWETHReward - totalWETHExcluded;
        }           
    }

    function getElapsedTime() internal view returns (uint256) {
        return block.timestamp - startTime;
    }
}
