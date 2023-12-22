pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./InterestTokenDeer.sol";

contract DeerLock {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant APR = 15; // 15% APR
    uint256[6] public lockDurations = [7, 15, 30, 60, 120, 240]; // Time to Plans
    uint256 public totalDeposited;
    uint256 public totalInterestGenerated;
    uint256 public totalWithdrawn;
    address public addressContractinterestTokenDeer;
    uint256 public interestTokenDeerBalances;

    IERC20 public deertoken;

    InterestTokenDeer public interestTokenDeer;

    struct Deposit {
        uint256 amount;
        uint256 lockTimestamp;
        uint256 unlockTimestamp;
        uint256 interest;
        uint256 daylock;
        bool claimed;
    }

    struct Claim {
        uint256 amountpay;
        uint256 timestamp;
        uint256 interest;
        uint256 daylock;
        uint256 lockTimestamp;
        uint256 unlockTimestamp;
    }
    struct AllClaim {
        uint256 amount;
        uint256 timestamp;
        uint256 interest;
        uint256 daylock;
        uint256 lockTimestamp;
        uint256 unlockTimestamp;
        address user;
    }
    struct UserSummary {
        uint256 totalDeposited;
        uint256 totalInterestGenerated;
        uint256 totalWithdrawn;
    }
    struct History {
        uint256 date;
        address user;
        string typetnx;
        uint256 amountpayment;
    }

    mapping(address => mapping(uint256 => Deposit)) public deposits;
    mapping(address => UserSummary) public userSummaries;
    mapping(address => Claim) public historyClaims;

    AllClaim[] public historyAllClaims;
    History[] public historyLog;

    event DepositAdded(address indexed user, uint256 amount, uint256 duration);

    constructor(address _interestTokenDeer, address _token) {
        addressContractinterestTokenDeer = _interestTokenDeer;
        interestTokenDeer = InterestTokenDeer(addressContractinterestTokenDeer);
        deertoken = IERC20(_token);
    }

    function deposit(uint256 _amount, uint256 _durationIndex) external {
        require(_amount > 10, "Amount must be greater than 10");
        require(
            lockDurations[_durationIndex] >= 7,
            "Select amount of days greater than 7"
        );
        uint256 duration = lockDurations[_durationIndex] * 1 days; // cambio en prod a days

        deertoken.safeTransferFrom(msg.sender, address(this), _amount);
        Deposit storage deposit = deposits[msg.sender][_durationIndex];

        uint256 interest = calculateInterest(
            _amount,
            lockDurations[_durationIndex]
        );

        if (deposit.amount > 0) {
            deposit.amount = deposit.amount.add(_amount);
            deposit.lockTimestamp = block.timestamp;
            deposit.unlockTimestamp = block.timestamp.add(duration);
            deposit.interest = deposit.interest.add(interest);
        } else {
            deposits[msg.sender][_durationIndex] = Deposit(
                _amount,
                block.timestamp,
                block.timestamp + duration,
                interest,
                lockDurations[_durationIndex],
                false
            );
        }

        userSummaries[msg.sender].totalDeposited = userSummaries[msg.sender]
            .totalDeposited
            .add(_amount);
        userSummaries[msg.sender].totalInterestGenerated = userSummaries[
            msg.sender
        ].totalInterestGenerated.add(interest);
        totalDeposited = totalDeposited.add(_amount);
        totalInterestGenerated = totalInterestGenerated.add(interest);
        History memory logHistory = History({
            amountpayment: _amount,
            date: block.timestamp,
            user: msg.sender,
            typetnx: "deposit"
        });
        historyLog.push(logHistory);

        emit DepositAdded(msg.sender, _amount, duration);
    }

    function viewHistoy() public view returns (History[] memory) {
        return historyLog;
    }

    function viewHistyClaims() public view returns (AllClaim[] memory) {
        return historyAllClaims;
    }

    function calculateInterest(
        uint256 _amount,
        uint256 _duration
    ) public view returns (uint256) {
        uint256 num = uint256(0.0004109589 * 10 ** 18);
        uint256 dailyInterestRate = num;
        uint256 interestDaily = _amount.mul(dailyInterestRate).div(1e18);
        uint256 totalInterest = interestDaily.mul(_duration);
        uint256 interestTokenDeerBalance = interestTokenDeer.balance();
        if (interestTokenDeerBalance == 0) {
            return 0;
        }
        if (totalInterest > interestTokenDeerBalance) {
            totalInterest = interestTokenDeerBalance;
        }
        return totalInterest;
    }

    function viewBalanceDeer() public view returns (uint256) {
        uint256 interestTokenDeerBalance = interestTokenDeer.balance();
        return interestTokenDeerBalance;
    }

    function withdraw(uint256 _durationIndex) external {
        Deposit storage deposit = deposits[msg.sender][_durationIndex];
        require(!deposit.claimed, "El deposito ya ha sido retirado.");
        require(
            block.timestamp >= deposit.unlockTimestamp,
            "El deposito aun esta bloqueado."
        );

        deposit.claimed = true;

        IERC20 token = IERC20(interestTokenDeer.token());
        token.safeTransfer(msg.sender, deposit.amount);
        uint256 interestTokenDeerBalance = deertoken.balanceOf(
            addressContractinterestTokenDeer
        );

        if (interestTokenDeerBalance >= deposit.interest) {
            interestTokenDeer.withdrawInterest(msg.sender, deposit.interest);
        }

        historyClaims[msg.sender].amountpay = deposit.amount;
        historyClaims[msg.sender].timestamp = block.timestamp;
        historyClaims[msg.sender].interest = deposit.interest;
        historyClaims[msg.sender].daylock = deposit.daylock;
        historyClaims[msg.sender].lockTimestamp = deposit.lockTimestamp;
        historyClaims[msg.sender].unlockTimestamp = deposit.unlockTimestamp;

        historyAllClaims.push(
            AllClaim(
                deposit.amount,
                block.timestamp,
                deposit.interest,
                deposit.daylock,
                deposit.lockTimestamp,
                deposit.unlockTimestamp,
                msg.sender
            )
        );

        userSummaries[msg.sender].totalWithdrawn = userSummaries[msg.sender]
            .totalWithdrawn
            .add(deposit.amount + deposit.interest);

        totalWithdrawn = totalWithdrawn.add(deposit.amount + deposit.interest);
        History memory logHistory = History({
            amountpayment: deposit.amount,
            date: block.timestamp,
            user: msg.sender,
            typetnx: "withdrawn"
        });
        historyLog.push(logHistory);

        delete deposits[msg.sender][_durationIndex];
    }

    function totalClaims(address _user) public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < historyAllClaims.length; i++) {
            if (msg.sender == _user) {
                total = total.add(historyAllClaims[i].amount).add(
                    historyAllClaims[i].interest
                );
            }
        }
        return total;
    }
}

