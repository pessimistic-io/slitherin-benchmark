// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";

interface ISKAL is IERC20 {
    /* */

    function changeFarmAddress(address _address) external;

    function changeControlCenter(address _address) external;

    function changeTransferFeeExclusionStatus(
        address target,
        bool value
    ) external;

    function killswitch() external;

    function controlledMint(uint256 _amount) external;

    event SwapAndLiquify(
        uint256 sklPart,
        uint256 sklForEthPart,
        uint256 ethPart,
        uint256 liquidity
    );

    event TradingHalted(uint256 timestamp);
    event TradingResumed(uint256 timestamp);
    event TransferFeeExclusionStatusUpdated(address target, bool value);
    /* */
} 

interface IsSKAL is IERC20 {
    function enter(uint256 _amount) external;

    function leave(uint256 _amount) external;

    function enterFor(uint256 _amount, address _to) external;

    function killswitch() external;

    function setCompoundingEnabled(bool _enabled) external;

    function setMaxTxAndWalletBPS(uint256 _pid, uint256 bps) external;

    function rescueToken(address _token, uint256 _amount) external;

    function rescueETH(uint256 _amount) external;

    function excludeFromDividends(address account, bool excluded) external;

    function upgradeDividend(address payable newDividendTracker) external;

    function impactFeeStatus(bool _value) external;

    function setImpactFeeReceiver(address _feeReceiver) external;

    function SKLToSSKL(
        uint256 _sklAmount,
        bool _impactFeeOn
    )
        external
        view
        returns (uint256 sklAmount, uint256 swapFee, uint256 impactFee);

    function sSKLToSKL(
        uint256 _sSKLAmount,
        bool _impactFeeOn
    )
        external
        view
        returns (uint256 sklAmount, uint256 swapFee, uint256 impactFee);

    event TradingHalted(uint256 timestamp);
    event TradingResumed(uint256 timestamp);
}

interface ISKALReferral {
    /**
     * @dev Record referral.
     */
    function recordReferral(address user, address referrer) external;

    /**
     * @dev Record referral commission.
     */
    function recordReferralCommission(
        address referrer,
        uint256 commission
    ) external;

    /**
     * @dev Get the referrer address that referred the user.
     */
    function getReferrer(address user) external view returns (address);

    function getOutstandingCommission(
        address _referrer
    ) external view returns (uint256 amount);

    function debitOutstandingCommission(
        address _referrer,
        uint256 _debit
    ) external;

    function debitAndGetSSKL(address _referrer, uint256 _debit) external;

    function getTotalComission(
        address _referrer
    ) external view returns (uint256);

    function updateOperator(address _newPayer) external;

    function updateVesting(address _newVesting) external;
}

contract SkalableReferral is Ownable,ISKALReferral {
    mapping(address => address) public referrers; // referred address => referrer address
    mapping(address => uint256) public countReferrals; // referrer address => referrals count
    mapping(address => uint256) public totalReferralCommissions; // referrer address => total referral commissions
    mapping(address => uint256) public outstandingCommissions;
    // mapping(address => address[])public referrals; //referrer address => referred addresses
    address public sSKL;
    address public skl;
    event ReferralRecorded(address indexed user, address indexed referrer);
    event ReferralCommissionRecorded(
        address indexed referrer,
        uint256 commission
    );
    event OperatorUpdated(address indexed operator, bool indexed status);
    event BulkRecord(ReferralObject[] objectArray);
    struct ReferralObject {
        address referrer;
        address user;
    }
    address public payer;
    address public vestingContract;
    //added control center for updating payer address function, which wasnt present before, removes the need for Ownable contract
   

    constructor(address _sklToken, address _sSKLToken)Ownable() {
      
        sSKL = _sSKLToken;
        skl = _sklToken;
        IERC20(skl).approve(sSKL, type(uint256).max);
    }

    //this is the function that will be called from offchain, takes an object array {address,address} as parameter
    function bulkRecordReferralFromOffchain(
        ReferralObject[] memory _objectArray
    ) public {
        require(msg.sender == payer, "Only payer can record referrers");
        for (uint256 i = 0; i < _objectArray.length; i++) {
            optimizedRecord(_objectArray[i].user, _objectArray[i].referrer);
        }
        emit BulkRecord(_objectArray);
    }

    function optimizedRecord(address _user, address _referrer) private {
        if (referrers[_user] == address(0)) {
            referrers[_user] = _referrer;
            countReferrals[_referrer]++;
        }
    }

    function recordReferral(address _user, address _referrer) public override {
        require(msg.sender == payer, "Only payer can record referrers");
        if (referrers[_user] == address(0)) {
            referrers[_user] = _referrer;
            countReferrals[_referrer]++;
            emit ReferralRecorded(_user, _referrer);
        }
    }

    function recordReferralCommission(
        address _referrer,
        uint256 _commission
    ) public override {
        require(
            msg.sender == vestingContract,
            "SKalable:Only vesting contract(farm) can record commission"
        );
        totalReferralCommissions[_referrer] += _commission;
        outstandingCommissions[_referrer] += _commission;
        emit ReferralCommissionRecorded(_referrer, _commission);
    }

    function getOutstandingCommission(
        address _referrer
    ) public view override returns (uint256 amount) {
        amount = outstandingCommissions[_referrer];
    }

    function getTotalComission(
        address _referrer
    ) public view override returns (uint256) {
        return totalReferralCommissions[_referrer];
    }

    //this function was exclusive to payer, but I removed the requirement so the person who is owed the comission can also claim it for themselves
    //payment not yet implemented
    function debitOutstandingCommission(
        address _referrer,
        uint256 _debit
    ) external override {
        require(
            msg.sender == _referrer || msg.sender == payer,
            "SKalable:Only referrer and payer"
        );
        require(
            getOutstandingCommission(_referrer) >= _debit,
            "SKalable:Insufficent outstanding balance"
        );
        outstandingCommissions[_referrer] -= _debit;
        ISKAL(skl).controlledMint(_debit);
        IERC20(skl).transfer(_referrer, _debit);
        //MINT
    }

    function debitAllOutstandingComissions() external {
        address user = _msgSender();
        uint amountToClaim = getOutstandingCommission(user);
        if (amountToClaim > 0) {
            outstandingCommissions[user] -= amountToClaim;
            ISKAL(skl).controlledMint(amountToClaim);
            IERC20(skl).transfer(user, amountToClaim);
        }
    }

    function debitAndGetSSKL(
        address _referrer,
        uint256 _debit
    ) external override {
        require(
            msg.sender == _referrer || msg.sender == payer,
            "SKalable:Only referrer and payer"
        );
        require(
            getOutstandingCommission(_referrer) >= _debit,
            "SKalable:Insufficent outstanding balance"
        );
        outstandingCommissions[_referrer] -= _debit;
        ISKAL(skl).controlledMint(_debit);
        IsSKAL(sSKL).enterFor(_debit, _referrer);
    }

    function debitAllOutstandingComissionsAndGetsSKL() external {
        address user = _msgSender();
        uint amountToClaim = getOutstandingCommission(user);
        if (amountToClaim > 0) {
            outstandingCommissions[user] -= amountToClaim;
            ISKAL(skl).controlledMint(amountToClaim);
            IsSKAL(sSKL).enterFor(amountToClaim, user);
        }
    }

    function getTotalReferrals(
        address _referrer
    ) public view returns (uint256) {
        return countReferrals[_referrer];
    }

    // Get the referrer address that referred the user
    function getReferrer(address _user) public view override returns (address) {
        return referrers[_user];
    }

    //this is the wallet that will be used to sign the transaction needed to execute the recordReferral() functions
    function updateOperator(address _newPayer) external override onlyOwner{
     
        payer = _newPayer;
    }

    //this is the wallet that records all comissions
    function updateVesting(address _newVesting) external override onlyOwner{
    
        vestingContract = _newVesting;
    }
}

