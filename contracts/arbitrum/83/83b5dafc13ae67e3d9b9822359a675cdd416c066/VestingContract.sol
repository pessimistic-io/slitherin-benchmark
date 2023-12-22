// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./Initializable.sol";


contract VestingContract is Ownable,Initializable {
    using SafeERC20 for IERC20;

    IERC20 public aceToken;

	uint256 public startDate;//TGE date

    uint256 public constant DENOMINATOR = 10_000;


    struct VestingSchedule {
		uint256 totalAmount; // The total amount of tokens to be vested (total_supply * supplyPerc %).
        uint256 tgePerc; // The percentage of tokens to be released at TGE.
        uint256 cliff; // The duration from the start time until the first claim can be made.
        uint256 vestingPrc; // The percentage of tokens to be released after each vesting period (in basis points, e.g., 5% is represented as 500).
        uint256 duration; // The total duration of the vesting schedule.
		uint256 released; // The amount of tokens that have already been claimed.
    }

    mapping(address => VestingSchedule) private vestingSchedules;

	uint256 public totalSaleAmount;
	uint256 public totalTokensTransferred;


    event Released(address receiver, uint256 released);

   

	function init(address _token,uint256 _amt) external initializer onlyOwner {
		require(_token != address(0), "Invalid token address");
        aceToken = IERC20(_token);
		totalSaleAmount = _amt;

	}

	function setStartDate(uint256 _tge) external onlyOwner{
		require(startDate == 0,"Already initialized");
        require(block.timestamp <= _tge, "Invalid start date");
		startDate = _tge;
	}

    function createVestingSchedule(
		address _account,
		uint256 _totalAmount,
		uint256 _tgePerc,
		uint256 _cliff,
		uint256 _vestingPrc,
		uint256 _duration
        ) external onlyOwner {
			require(_account!= address(0), "Address Zero");
            require(vestingSchedules[_account].totalAmount == 0, "Vesting already exists");
            require(
				_totalAmount > 0 , "Invalid Vesting Amount");
			require(_tgePerc <= DENOMINATOR , "Invalid Vesting Percentage");
            require(_vestingPrc <= DENOMINATOR , "Invalid Vesting Percentage");
			vestingSchedules[_account] = VestingSchedule(_totalAmount,_tgePerc,_cliff,_vestingPrc,_duration,0);
    }



    function release() external returns (uint256) {
        VestingSchedule storage vesting = vestingSchedules[msg.sender];
        require(vesting.totalAmount >  0, "Vesting schedule does not exist");
        uint256 unclaimed = getReleasableAmount(msg.sender);
        vesting.released += unclaimed;
        IERC20(aceToken).safeTransfer(msg.sender, unclaimed);
        emit Released(msg.sender, unclaimed);
        return unclaimed;
    }
	
    function getReleasableAmount(address beneficiary) public view returns (uint256) {
        VestingSchedule memory vestingSchedule = vestingSchedules[beneficiary];
        uint256 currentTime = block.timestamp;
        uint256 released;
        if (currentTime < startDate || vestingSchedule.totalAmount == vestingSchedule.released ) {
            return 0;
        } else {
            released = vestingSchedule.totalAmount * vestingSchedule.tgePerc / DENOMINATOR;
        }
        uint256 vestedPerPeriod = ((vestingSchedule.totalAmount) * vestingSchedule.vestingPrc) / DENOMINATOR;
        uint256 elapsedTime = currentTime - startDate;

        if (elapsedTime >= vestingSchedule.cliff) {
            uint256 vestedAmount = (((elapsedTime - vestingSchedule.cliff)) / 30 days)  * vestedPerPeriod;
            released += vestedAmount;
        }
        if (elapsedTime >=  vestingSchedule.duration + vestingSchedule.cliff) {
            return vestingSchedule.totalAmount - vestingSchedule.released;
        }
        released -= vestingSchedule.released;
        return released;
    }

    // to transfer tokens to lauchpads
	function transferFunds(address _receiver,uint256 _amt) external onlyOwner {
		require(_receiver != address(0),"Invalid receiver address");
        require(totalTokensTransferred + _amt < totalSaleAmount,"");
		totalTokensTransferred += _amt;
		 IERC20(aceToken).safeTransfer(_receiver, _amt);
	}

    function getAccVesting(address _acc)  external view returns(
		uint256 totalAmount,
        uint256 tgePerc,
        uint256 cliff,
        uint256 vestingPrc,
        uint256 duration,
		uint256 released){
        VestingSchedule memory _vesting = vestingSchedules[_acc];
		totalAmount = _vesting.totalAmount;
		tgePerc = _vesting.tgePerc;
        cliff = _vesting.cliff;
        vestingPrc = _vesting.vestingPrc;
        duration = _vesting.duration;
		released = _vesting.released;
    }


    function renounceOwnership() public override onlyOwner {
        revert("can't renounceOwnership"); 
    }


}
