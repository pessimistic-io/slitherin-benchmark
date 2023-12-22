// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;

import "./SafeMath.sol";

import "./ERC20Permit.sol";

import "./IKarsha.sol";
import "./IsPana.sol";
import "./IStaking.sol";
import "./PanaAccessControlled.sol";

contract sPana is IsPana, ERC20Permit, PanaAccessControlled {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;

    /* ========== EVENTS ========== */

    event LogSupply(uint256 indexed epoch, uint256 totalSupply);
    event LogRebase(uint256 indexed epoch, uint256 rebase, uint256 index);
    event LogStakingContractUpdated(address stakingContract);
    event ToggleTransfer(bool disableTransfer);

    /* ========== MODIFIERS ========== */

    modifier onlyStakingContract() {
        require(msg.sender == stakingContract, "StakingContract:  call is not staking contract");
        _;
    }

    /* ========== DATA STRUCTURES ========== */

    struct Rebase {
        uint256 epoch;
        uint256 rebase; // 18 decimals
        uint256 totalStakedBefore;
        uint256 totalStakedAfter;
        uint256 amountRebased;
        uint256 index;
        uint256 blockNumberOccured;
    }

    /* ========== STATE VARIABLES ========== */

    address internal initializer;

    uint256 internal INDEX; // Index Gons - tracks rebase growth

    address public stakingContract; // balance used to calc rebase
    bool internal disableTransfer;//toggle disable transfer in sPana
    IKarsha public KARSHA; // additional staked supply (governance token)

    Rebase[] public rebases; // past rebase data

    uint256 private constant MAX_UINT256 = type(uint256).max;
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 5_000_000 * 10**18;

    // TOTAL_GONS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that _gonsPerFragment is an integer.
    // Use the highest value that fits in a uint256 for max granularity.
    uint256 private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_GONS + 1) - 1) / 2
    uint256 private constant MAX_SUPPLY = ~uint128(0); // (2^128) - 1

    uint256 private _gonsPerFragment;
    mapping(address => uint256) private _gonBalances;

    mapping(address => mapping(address => uint256)) private _allowedValue;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _authority) ERC20("Staked PANA", "sPANA", 18) ERC20Permit("Staked PANA") 
        PanaAccessControlled(IPanaAuthority(_authority)) {
        initializer = msg.sender;
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);
        disableTransfer = true;
    }

    /* ========== INITIALIZATION ========== */

    function setIndex(uint256 _index) external {
        require(msg.sender == initializer, "Initializer:  caller is not initializer");
        require(INDEX == 0, "Cannot set INDEX again");
        INDEX = gonsForBalance(_index);
    }

    function setKarsha(address _karsha) external {
        require(msg.sender == initializer, "Initializer:  caller is not initializer");
        require(address(KARSHA) == address(0), "KARSHA:  KARSHA already set");
        require(_karsha != address(0), "KARSHA:  KARSHA is not a valid contract");
        KARSHA = IKarsha(_karsha);
    }

    // do this last
    function initialize(address _stakingContract) external {
        require(msg.sender == initializer, "Initializer:  caller is not initializer");

        require(_stakingContract != address(0), "Staking");
        stakingContract = _stakingContract;
        _gonBalances[stakingContract] = TOTAL_GONS;

        emit Transfer(address(0x0), stakingContract, _totalSupply);
        emit LogStakingContractUpdated(stakingContract);

        initializer = address(0);
    }
    
    function toggleTransfer() external onlyGovernor returns (bool) {
        disableTransfer=!disableTransfer;
        emit ToggleTransfer(disableTransfer);
        return disableTransfer;
    }

    function setStakingContract(address _stakingContract) external onlyGovernor {
        require(_stakingContract != address(0), "Zero address: StakingContract");
        _gonBalances[_stakingContract] = _gonBalances[stakingContract];
        _gonBalances[stakingContract] = 0;
        stakingContract = _stakingContract;
    }

    /* ========== REBASE ========== */

    /**
        @notice increases rPANA supply to increase staking balances relative to profit_
        @param profit_ uint256
        @return uint256
     */
    function rebase(uint256 profit_, uint256 epoch_) public override onlyStakingContract returns (uint256) {
        uint256 rebaseAmount;
        uint256 circulatingSupply_ = circulatingSupply();
        if (profit_ == 0) {
            emit LogSupply(epoch_, _totalSupply);
            emit LogRebase(epoch_, 0, index());
            return _totalSupply;
        } else if (circulatingSupply_ > 0) {
            rebaseAmount = profit_.mul(_totalSupply).div(circulatingSupply_);
        } else {
            rebaseAmount = profit_;
        }

        _totalSupply = _totalSupply.add(rebaseAmount);

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS.div(_totalSupply);

        _storeRebase(circulatingSupply_, profit_, epoch_);

        return _totalSupply;
    }

    /**
        @notice emits event with data about rebase
        @param previousCirculating_ uint
        @param profit_ uint
        @param epoch_ uint
     */
    function _storeRebase(
        uint256 previousCirculating_,
        uint256 profit_,
        uint256 epoch_
    ) internal {
        uint256 rebasePercent = 0;
        if(previousCirculating_ > 0) {
            rebasePercent = profit_.mul(1e18).div(previousCirculating_);
        }
        rebases.push(
            Rebase({
                epoch: epoch_,
                rebase: rebasePercent, // 18 decimals
                totalStakedBefore: previousCirculating_,
                totalStakedAfter: circulatingSupply(),
                amountRebased: profit_,
                index: index(),
                blockNumberOccured: block.number
            })
        );

        emit LogSupply(epoch_, _totalSupply);
        emit LogRebase(epoch_, rebasePercent, index());
    }

    /* ========== MUTATIVE FUNCTIONS =========== */

    function transfer(address to, uint256 value) public override(IERC20, ERC20) returns (bool) {
        require(disableTransfer == false, "Transfer function is disabled");
        uint256 gonValue = gonsForBalance(value);

        _gonBalances[msg.sender] = _gonBalances[msg.sender].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);

        //todo:if transfer is called by sPana token
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override(IERC20, ERC20) returns (bool) {
        require(disableTransfer == false, "Transfer function is disabled");
        _allowedValue[from][msg.sender] = _allowedValue[from][msg.sender].sub(value);
        emit Approval(from, msg.sender, _allowedValue[from][msg.sender]);

        uint256 gonValue = gonsForBalance(value);
        _gonBalances[from] = _gonBalances[from].sub(gonValue);
        _gonBalances[to] = _gonBalances[to].add(gonValue);
        
        //todo:if transferFrom is called by sPana token
        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public override(IERC20, ERC20) returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public override returns (bool) {
        _approve(msg.sender, spender, _allowedValue[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public override returns (bool) {
        uint256 oldValue = _allowedValue[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _approve(msg.sender, spender, 0);
        } else {
            _approve(msg.sender, spender, oldValue.sub(subtractedValue));
        }
        return true;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _approve(
        address owner,
        address spender,
        uint256 value
    ) internal virtual override {
        _allowedValue[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function balanceOf(address who) public view override(IERC20, ERC20) returns (uint256) {
        return _gonBalances[who].div(_gonsPerFragment);
    }

    function gonsForBalance(uint256 amount) public view override returns (uint256) {
        return amount.mul(_gonsPerFragment);
    }

    function balanceForGons(uint256 gons) public view override returns (uint256) {
        return gons.div(_gonsPerFragment);
    }

    // toKARSHA converts an sPANA/PANA balance to KARSHA terms. KARSHA is an 18 decimal token. balance given is in 18 decimal format.
    function toKARSHA(uint256 amount) external view override returns (uint256) {
        return KARSHA.balanceTo(amount);
    }

    // fromKARSHA converts a KARSHA balance to sPANA/PANA terms. sPANA is a 18 decimal token. balance given is in 18 decimal format.
    function fromKARSHA(uint256 amount) external view override returns (uint256) {
        return KARSHA.balanceFrom(amount);
    }

    // Staking contract holds excess sKARSHA
    function circulatingSupply() public view override returns (uint256) {
        return
            _totalSupply.sub(balanceOf(stakingContract)).add(KARSHA.balanceFrom(IERC20(address(KARSHA)).totalSupply()));
    }

    function index() public view override returns (uint256) {
        return balanceForGons(INDEX);
    }

    function allowance(address owner_, address spender) public view override(IERC20, ERC20) returns (uint256) {
        return _allowedValue[owner_][spender];
    }
}

