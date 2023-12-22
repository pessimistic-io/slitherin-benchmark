// SPDX-License-Identifier: MIT AND AGPL-3.0-or-later

pragma solidity =0.8.9;

import "./Ownable.sol";

import "./IERC20.sol";

import "./ISenecaVesting.sol";

/**
 * @dev Implementation of the {ISenecaVesting} interface.
 *
 * The straightforward vesting contract that gradually releases a
 * fixed supply of tokens to multiple vest parties over a 90 days
 * window.
 *
 * The token expects the {begin} hook to be invoked the moment
 * it is supplied with the necessary amount of tokens to vest,
 * which should be equivalent to the time the {setComponents}
 * function is invoked on the seneca token.
 */
contract SenecaVestingAirdrop is ISenecaVesting, Ownable {

    /* ========== STATE VARIABLES ========== */

    // The seneca token
    IERC20 public immutable seneca;

    // The start of the vesting period
    uint256 public start;

    // The end of the vesting period
    uint256 public end;

    address public DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    string public presaleName = 'Seneca Airdrop';

    // The status of each vesting member (Vester)
    mapping(address => Vester) public vest;
    address[] public vesterArray;

    // The address of an Operator contract.
    address public operator;

    uint256 internal constant _VESTING_DURATION = 90 days;

    address internal constant _ZERO_ADDRESS = address(0);

    event RewardsReturned(address indexed operator, uint256 totalUnclaimed);

    modifier hasStarted() {
        _hasStarted();
        _;
    }

    modifier onlyOperator() {
        _onlyOperator();
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    /**
     * @dev Initializes the contract's vesters and vesting amounts as well as sets
     * the seneca token address.
     *
     * It conducts a sanity check to ensure that the total vesting amounts specified match
     * the team allocation to ensure that the contract is deployed correctly.
     *
     * Additionally, it transfers ownership to the seneca contract that needs to consequently
     * initiate the vesting period via {begin} after it mints the necessary amount to the contract.
     */
    constructor(IERC20 _seneca, address _operator) {
        require(
            _seneca != IERC20(_ZERO_ADDRESS) && _operator != _ZERO_ADDRESS,
            "SenecaVesting::constructor: Misconfiguration"
        );

        seneca = _seneca;
        operator = _operator;
    }

    /* ========== VIEWS ========== */

    /**
     * @dev Returns the amount a user can claim at a given point in time.
     *
     * Requirements:
     * - the vesting period has started
     */
    function getClaim(address _vester)
        external
        view
        override
        hasStarted
        returns (uint256 vestedAmount)
    {
        Vester memory vester = vest[_vester];
        return
            _getClaim(
                vester.amount,
                vester.startingAmount,
                vester.lastClaim,
                vester.start,
                vester.end
            );
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @dev Allows a user to claim their pending vesting amount of the vested claim
     *
     * Emits a {Vested} event indicating the user who claimed their vested tokens
     * as well as the amount that was vested.
     *
     * Requirements:
     *
     * - the vesting period has started
     * - the caller must have a non-zero vested amount
     */
    function claim() external override returns (uint256 vestedAmount) {
        Vester memory vester = vest[msg.sender];

        require(
            vester.start != 0,
            "SenecaVesting: incorrect start val"
        );

        require(
            vester.start < block.timestamp,
            "SenecaVesting: Not Started Yet"
        );

        vestedAmount = _getClaim(
            vester.amount,
            vester.startingAmount,
            vester.lastClaim,
            vester.start,
            vester.end
        );

        require(vestedAmount != 0, "SenecaVesting: Nothing to claim");

        vester.amount -= uint192(vestedAmount);
        vester.lastClaim = uint64(block.timestamp);

        vest[msg.sender] = vester;

        emit Vested(msg.sender, vestedAmount);

        seneca.transfer(msg.sender, vestedAmount);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @dev Allows the vesting period to be initiated.
     *
     * Emits a {VestingInitialized} event from which the start and
     * end can be calculated via it's attached timestamp.
     *
     * Requirements:
     *
     * - the caller must be the owner (seneca token)
     */
    function begin(address[] calldata vesters, uint192[] calldata amounts)
        external
        override
        onlyOperator
    {
        require(
            vesters.length == amounts.length,
            "SenecaVesting: Vesters/Amounts length mismatch"
        );

        uint256 total;
    
        for (uint256 i = 0; i < vesters.length; ++i) {
            require(
                amounts[i] != 0,
                "SenecaVesting: Incorrect Amount"
            );
            require(
                vesters[i] != _ZERO_ADDRESS,
                "SenecaVesting: Vester Zero Address"
            );
            require(
                vest[vesters[i]].amount == 0,
                "SenecaVesting: Duplicate Vester Entry"
            );
            vesterArray.push(vesters[i]);
            vest[vesters[i]] = Vester(
                amounts[i],
                amounts[i],
                0,
                0,
                0,
                false
            );
            total = total + amounts[i];
        }
        

        emit VestingInitialized(_VESTING_DURATION);

        renounceOwnership();
    }

    function initializeVesting() public onlyOperator{
        
        uint256 _start = block.timestamp;
        uint256 _end = block.timestamp + _VESTING_DURATION;

        start = _start;
        end = _end;

        for (uint256 i = 0; i < vesterArray.length; ++i) {
            Vester storage vester = vest[vesterArray[i]];
    
            vester.start += uint128(start);
            vester.end += uint128(end);
        }

    }

    /**
     * @dev Adds a new vesting schedule to the contract.
     *
     * Requirements:
     * - Only {Operator} can call.
     */
    function vestFor(address user, uint256 amount)
        external
        override
        onlyOperator
    {
        require(
            amount <= type(uint192).max,
            "SenecaVesting: Amount Overflows uint192"
        );
        require(
            vest[user].amount == 0,
            "SenecaVesting: Already a vester"
        );
        vesterArray.push(user);
        vest[user] = Vester(
            uint192(amount),
            uint192(amount),
            0,
            0,
            0,
            false
        );
        seneca.transferFrom(msg.sender, address(this), amount);

        emit VestingCreated(user, amount);
    }

    function claimTGE() external returns (uint256 tgeAmount) {
        Vester memory vester = vest[msg.sender];
    

        require(vester.amount != 0, "SenecaVesting: Nothing to claim");
        require(vester.start != 0, "SenecaVesting: Incorrect Vesting Type");
        require(vester.start < block.timestamp, "SenecaVesting: Not Started Yet");
        require(!isTGEClaimed(msg.sender), "SenecaVesting: TGE already claimed");
        

        tgeAmount = vester.amount * 10 / 100;

        vester.amount -= uint192(tgeAmount);
        vester.hasClaimedTGE = true;

        vest[msg.sender] = vester;

        emit Vested(msg.sender, tgeAmount);

        seneca.transfer(msg.sender, tgeAmount);
    }

    function isTGEClaimed(address vestingParticipant) public view returns(bool isClaimed){
        Vester memory vester = vest[vestingParticipant];
        return vester.hasClaimedTGE;
    }

    /**
     * @dev Returns the unclaimed tokens to the operator if the first vester's
     * end period has been reached.
     */
    function returnUnclaimedTokens() external onlyOperator {
        require(vesterArray.length > 0, "SenecaVesting: No vesters available");

        Vester storage firstVester = vest[vesterArray[0]];

        require(
            firstVester.end > 0 && firstVester.end <= block.timestamp,
            "SenecaVesting: Vester period has not ended"
        );

        uint256 totalUnclaimed = seneca.balanceOf(address(this));

        // Transfer the unclaimed amount to the operator
        seneca.transfer(operator, totalUnclaimed);

        emit RewardsReturned(operator, totalUnclaimed);
    }


    /* ========== PRIVATE FUNCTIONS ========== */

    function _getClaim(
        uint256 amount,
        uint256 startingAmount,
        uint256 lastClaim,
        uint256 _start,
        uint256 _end
    ) private view returns (uint256) {
        if (block.timestamp >= _end) return amount;
        if (lastClaim == 0) lastClaim = _start;
        startingAmount;

        return (amount * (block.timestamp - lastClaim)) / (_end - lastClaim);
    }

    /**
     * @dev Validates that the vesting period has started
     */
    function _hasStarted() private view {
        require(
            start != 0,
            "SenecaVesting: Vesting hasn't started yet"
        );
    }

    /*
     * @dev Ensures that only Operator is able to call a function.
     **/
    function _onlyOperator() private view {
        require(
            msg.sender == operator,
            "SenecaVesting: Only Operator is allowed to call"
        );
    }

    function transferOperator(address newOperator) public onlyOperator {
        operator = newOperator;
    }

}

