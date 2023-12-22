// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.16;
pragma experimental ABIEncoderV2;

// ====================================================================
// ====================== Balancer.sol ==============================
// ====================================================================

// Primary Author(s)
// MAXOS Team: https://maxos.finance/

import "./Stabilizer.sol";
import "./ISweep.sol";
import "./IAMM.sol";
import "./SafeMath.sol";
import "./TransferHelper.sol";
import "./IUniswapV3Factory.sol";
import "./Owned.sol";
import "./IERC20.sol";

contract Balancer is Owned {
    using SafeMath for uint256;

    // Variables
    address public balancer;
    uint8 public delay; // Days

    // Uniswap v3
    IUniswapV3Factory public univ3_factory;

    // Tokens
    IERC20 public USDX;
    ISweep public SWEEP;

    // Enums
    enum Status {
        Created,
        Executed,
        Canceled
    }

    // Proposal tracking
    mapping(address => Proposal[]) public proposals;

    // Constants
    uint256 private constant DAY_TIMESTAMP = 24 * 60 * 60;
    uint256 private constant PRICE_PRECISION = 1e6;
    uint256 private constant PRICE_MISSING_MULTIPLIER = 1e12;

    // Structs
    struct Proposal {
        uint256 amount; // Sweep Amount
        uint256 createdDT; // Created date.
        Status status; // Status of a Proposal.
    }

    // Events
    event Request(address stabilizer, uint256 amount);
    event Execute(address stabilizer, uint256 amount);
    event Cancel(address stabilizer);
    event Withdraw(address token, uint256 amount);
    event DelayChanged(uint8 delay);

    constructor(
        address _owner_address,
        address _balancer_address,
        address _usdx_address,
        address _sweep_address,
        address _uniswap_factory_address,
        uint8 _delay
    ) Owned(_owner_address) {
        balancer = _balancer_address;
        univ3_factory = IUniswapV3Factory(_uniswap_factory_address);
        USDX = IERC20(_usdx_address); // USDC
        SWEEP = ISweep(_sweep_address); // Sweep
        delay = _delay;
    }

    /* ========== Modifies ========== */

    modifier onlyBalancer() {
        require(msg.sender == balancer, "only balancer");
        _;
    }

    /* ========== Views ========== */

    /**
     * @notice getAmountToPeg
     * Get Sweep amount to peg to the target price.
     * @return amount Sweep amount.
     * @return status Request Status.
     * @dev If the status is true, banker might repay SWEEP. If the staus is false, banker should borrow SWEEP.
     */
    function getAmountToPeg() public view returns (uint256 amount, bool status) {
        address uniswapV3Pool = univ3_factory.getPool(address(SWEEP), address(USDX), 3000);
        uint256 sweep_amount = SWEEP.balanceOf(uniswapV3Pool);
        uint256 usdx_amount = USDX.balanceOf(uniswapV3Pool);
        uint256 target_price = SWEEP.target_price();
        uint256 radicand = target_price.mul(sweep_amount).mul(usdx_amount).mul(PRICE_MISSING_MULTIPLIER).div(PRICE_PRECISION);
        uint256 root = radicand.sqrt();

        if (root > sweep_amount) {
            amount = (root - sweep_amount).mul(997).div(1000);
            status = false;
        } else {
            amount = (sweep_amount - root).mul(997).div(1000);
            status = true;
        }
    }

    /**
     * @notice showProposals
     * Get all proposals of the banker.
     * @param banker Address to get proposals.
     */
    function showProposals(address banker) public view returns (Proposal[] memory) {
        return proposals[banker];
    }

    /**
     * @notice showProposal
     * Get latest proposal of the banker.
     * @param banker Address to get proposal.
     */
    function showProposal(address banker) public view returns (Proposal memory) {
        uint256 length = proposals[banker].length;
        Proposal memory tmp;
        if (length > 0) return proposals[banker][length - 1];
        else return tmp;
    }

    /**
     * @notice isDefaulted
     * Check whether the proposal is executed.
     * @param banker Address to check the status of a proposal.
     * @return bool True: is defaulted, False: not defaulted.
     */
    function isDefaulted(address banker) public view returns (bool) {
        uint256 length = proposals[banker].length;
        if(length > 0) {
            Proposal memory proposal = proposals[banker][length - 1];
            bool isPassed = proposal.createdDT + (delay * DAY_TIMESTAMP) < block.timestamp;
            if(proposal.status == Status.Created && isPassed) {
                return true;
            }
        }

        return false;
    }

    /* ========== Settings ========== */

    /**
    * @notice Set Delay to execute the request.
    * @param _delay Days
    */
    function setDelay(uint8 _delay) public onlyBalancer {
        delay = _delay;

        emit DelayChanged(_delay);
    }

    /* ========== Actions ========== */

    /**
     * @notice Request
     * Create a request for banker to repay or borrow sweep.
     * @param stabilizer Address to execute this request.
     * @param amount Sweep amount.
     */
    function request(
        address stabilizer,
        uint256 amount
    ) public onlyBalancer {
        require(stabilizer != address(0), "Wrong Address.");
        Stabilizer stb = Stabilizer(stabilizer);
        address banker = stb.banker();
        uint256 length = proposals[banker].length;
        uint256 debt = stb.sweep_borrowed();
        require(debt >= amount, "Over Amount than debt.");

        if (length > 0) {
            Proposal memory last_proposal = proposals[banker][length - 1];
            require(last_proposal.status != Status.Created, "Not yet Executed.");
        }

        proposals[banker].push(
            Proposal(amount, block.timestamp, Status.Created)
        );

        emit Request(stabilizer, amount);
    }

    /**
     * @notice Execute
     * The banker executes a request for sweep repay or borrow.
     * @param stabilizer Address to execute this request.
     */
    function execute(
        address stabilizer
    ) public {
        require(stabilizer != address(0), "Wrong Address.");
        Stabilizer stb = Stabilizer(stabilizer);
        address banker = stb.banker();
        uint256 length = proposals[banker].length;
        require(length > 0, "Non-Existent Proposal.");
        Proposal storage proposal = proposals[banker][length - 1];
        bool isPassed = proposal.createdDT + (delay * DAY_TIMESTAMP) < block.timestamp;
        require(proposal.status == Status.Created && !isPassed, "Can't Execute.");
        proposal.status = Status.Executed;
        if(banker == msg.sender) {
            stb.burn(proposal.amount);
        } else {
            SWEEP.transferFrom(msg.sender, address(this), proposal.amount);
            SWEEP.approve(stabilizer, proposal.amount);
            stb.repay(proposal.amount);
        }

        emit Execute(stabilizer, proposal.amount);
    }

    /**
     * @notice Cancel
     * The Balancer cancel the latest request of a stabilizer.
     * @param stabilizer Address to cancel the request.
     */
    function cancel(
        address stabilizer
    ) public onlyBalancer {
        require(stabilizer != address(0), "Wrong Address.");
        Stabilizer stb = Stabilizer(stabilizer);
        address banker = stb.banker();
        uint256 length = proposals[banker].length;
        require(length > 0, "Non-Existent Proposal.");
        Proposal storage proposal = proposals[banker][length - 1];
        proposal.status = Status.Canceled;

        emit Cancel(stabilizer);
    }
}

