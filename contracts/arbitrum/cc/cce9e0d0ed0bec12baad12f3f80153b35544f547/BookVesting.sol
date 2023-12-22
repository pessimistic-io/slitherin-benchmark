// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import { Ownable } from "./Ownable.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { IBookToken } from "./IBookToken.sol";

contract BookVesting is Ownable, ReentrancyGuard {

    mapping(address => uint256) public allotments;
    mapping(address => uint256) public withdrawn;

    address public immutable book;

    uint256 public immutable startTime; // beginning of 60 month vesting window (unix timestamp)
    uint256 public immutable totalAllotments; // Total $BOOK tokens vested
    uint256 public totalWithdrawn;
    bool private allotmentsSet;

    string public CONTRACT_DESCRIPTION;
    uint256 private constant A_FACTOR = 10**18;
    uint256 public constant PERIOD_DIVISOR = 16666666666666666;
    
    event TokensClaimed(address indexed account, uint256 amountBook);
    event AccountUpdated(address oldAccount, address newAccount, uint256 allotted, uint256 withdrawn);
   
    constructor(uint256 _startTime, uint256 _totalVested, string memory _description) {
        startTime = _startTime; 
        totalAllotments = _totalVested;
        CONTRACT_DESCRIPTION = _description;
        book = msg.sender;
    }

    function setAllotments(
        address[] calldata _accounts, 
        uint16[] calldata _percentShare
    ) external onlyOwner returns (int256 allocated, int256 variance) {
        require(!allotmentsSet, "Allotments already set");
        require(_accounts.length == _percentShare.length, "Array length mismatch");
        uint256 s;
        for (uint256 i = 0; i < _accounts.length; i++) {
            require(allotments[_accounts[i]] == 0, "Duplicate account");
            s = (totalAllotments * _percentShare[i]) / 10000;
            allotments[_accounts[i]] = s;
            allocated += int256(s);
        }
        variance = int256(totalAllotments) - allocated;
        require(variance < 0 ? variance > -1 ether : variance < 1 ether, "Incorrect amounts allotted");
        allotmentsSet = true;
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
        uint256 withdrawable = _calculateWithdrawableAmounts(msg.sender);
        require(withdrawable > 0, "Nothing to claim right now");

        IBookToken(book).mintVestedTokens(withdrawable, msg.sender);
        withdrawn[msg.sender] += withdrawable;
        totalWithdrawn += withdrawable;

        emit TokensClaimed(msg.sender, withdrawable);
    }

    function calculateWithdrawableAmounts(address _account) external view returns (uint256 withdrawable) {
        return _calculateWithdrawableAmounts(_account);
    }

    function claimableBook() external view returns (uint256 withdrawable) {
        if (block.timestamp < startTime) { return 0; }
        uint256 available = totalAllotments - totalWithdrawn; // amount left that can be claimed
        uint256 periodAmount = (totalAllotments * PERIOD_DIVISOR) / A_FACTOR; // 1/60th of original allotment;

        uint256 vestedTime = (getElapsedTime() / 30 days) + 1;
        uint256 unlocked = periodAmount * vestedTime;
        uint256 unclaimed = unlocked - totalWithdrawn;
        withdrawable = unclaimed < available ? unclaimed : available;
    }

    function _calculateWithdrawableAmounts(address _address) internal view returns (uint256 withdrawable) {
        if (block.timestamp < startTime) { return 0; }
        uint256 original = allotments[_address]; // initial allotment
        uint256 claimed = withdrawn[_address]; // amount user has claimed
        uint256 available = original - claimed; // amount left that can be claimed
        uint256 periodAmount = (original * PERIOD_DIVISOR) / A_FACTOR; // 1/60th of user's original allotment;

        uint256 vestedTime = (getElapsedTime() / 30 days) + 1;
        uint256 unlocked = periodAmount * vestedTime;
        uint256 unclaimed = unlocked - claimed;
        withdrawable = unclaimed < available ? unclaimed : available;    
    }

    function getElapsedTime() internal view returns (uint256) {
        return block.timestamp - startTime;
    }
}
