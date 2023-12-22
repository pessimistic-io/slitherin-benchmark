/*
        By Participating In 
       The Quantum Prosper Network 
     You Are Accelerating Your Wealth
With A Strong Network Of Beautiful Souls 

Telegram: https://t.me/QuantumProsperNetwork
Twitter: https://twitter.com/QuantumPN
*/

// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./IsQPN.sol";
import "./IStaking.sol";

/// @title   sQPN
/// @notice  Staked QPN
contract sQPN is IsQPN, ERC20 {
    /// EVENTS ///

    event LogSupply(uint256 indexed epoch, uint256 totalSupply);
    event LogRebase(uint256 indexed epoch, uint256 rebase, uint256 index);
    event LogStakingContractUpdated(address stakingContract);

    /// MODIFIERS ///

    modifier onlyStakingContract() {
        require(
            msg.sender == stakingContract,
            "StakingContract:  call is not staking contract"
        );
        _;
    }

    /// DATA STRUCTURES ///

    struct Rebase {
        uint256 epoch;
        uint256 rebase; // 18 decimals
        uint256 totalStakedBefore;
        uint256 totalStakedAfter;
        uint256 amountRebased;
        uint256 index;
        uint256 blockNumberOccured;
    }

    /// STATE VARIABLES ///

    address internal initializer;
    address public treasury;
    address public stakingContract; // balance used to calc rebase

    uint256 internal _totalSupply;
    uint256 internal INDEX; // Index Gons - tracks rebase growth

    uint256 private constant MAX_UINT256 = type(uint256).max;
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 250_000 * 10 ** 9;

    // TOTAL_GONS is a multiple of INITIAL_FRAGMENTS_SUPPLY so that _gonsPerFragment is an integer.
    // Use the highest value that fits in a uint256 for max granularity.
    uint256 private constant TOTAL_GONS =
        MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);

    // MAX_SUPPLY = maximum integer < (sqrt(4*TOTAL_GONS + 1) - 1) / 2
    uint256 private constant MAX_SUPPLY = ~uint128(0); // (2^128) - 1

    uint256 private _gonsPerFragment;

    Rebase[] public rebases; // past rebase data

    mapping(address => uint256) private _gonBalances;

    mapping(address => mapping(address => uint256)) private _allowedValue;

    /// CONSTRUCTOR ///

    constructor() ERC20("Staked QPN", "sQPN") {
        initializer = msg.sender;
        _totalSupply = INITIAL_FRAGMENTS_SUPPLY;
        _gonsPerFragment = TOTAL_GONS / _totalSupply;
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    /// INITIALIZATION ///

    /// @notice        Sets initial index
    /// @param _index  Initial index
    function setIndex(uint256 _index) external {
        require(
            msg.sender == initializer,
            "Initializer:  caller is not initializer"
        );
        require(INDEX == 0, "Cannot set INDEX again");
        INDEX = gonsForBalance(_index);
    }

    /// @notice                  Initialize contract
    /// @param _stakingContract  Address of staking contract
    /// @param _treasury         Address of treasury
    function initialize(address _stakingContract, address _treasury) external {
        require(
            msg.sender == initializer,
            "Initializer:  caller is not initializer"
        );

        require(_stakingContract != address(0), "Zero address: Staking");
        stakingContract = _stakingContract;
        _gonBalances[stakingContract] = TOTAL_GONS;

        require(_treasury != address(0), "Zero address: Treasury");
        treasury = _treasury;

        emit Transfer(address(0x0), stakingContract, _totalSupply);
        emit LogStakingContractUpdated(stakingContract);

        initializer = address(0);
    }

    /// REBASE ///

    /// @notice             Increases sQPN supply
    /// @param amount_      Amount to rebase for
    /// @param epoch_       Epoch number
    /// @return _newSupply  New total supply
    function rebase(
        uint256 amount_,
        uint256 epoch_
    ) public override onlyStakingContract returns (uint256 _newSupply) {
        uint256 rebaseAmount;
        uint256 circulatingSupply_ = circulatingSupply();
        if (amount_ == 0) {
            emit LogSupply(epoch_, _totalSupply);
            emit LogRebase(epoch_, 0, index());
            return _totalSupply;
        } else if (circulatingSupply_ > 0) {
            rebaseAmount = (amount_ * _totalSupply) / circulatingSupply_;
        } else {
            rebaseAmount = amount_;
        }

        _totalSupply = _totalSupply + rebaseAmount;

        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }

        _gonsPerFragment = TOTAL_GONS / _totalSupply;

        _storeRebase(circulatingSupply_, amount_, epoch_);

        return _totalSupply;
    }

    /// @notice                      Stores rebase
    /// @param previousCirculating_  Previous circ supply
    /// @param profit_               Amount of profic for epoch
    /// @param epoch_                Epoch number
    function _storeRebase(
        uint256 previousCirculating_,
        uint256 profit_,
        uint256 epoch_
    ) internal {
        uint256 rebasePercent;
        if (previousCirculating_ > 0)
            rebasePercent = (profit_ * 1e18) / previousCirculating_;
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

    /// MUTATIVE FUNCTIONS ///

    /// @notice       Transfer sQPN from msg.sender
    /// @param to     Address sending sQPN to
    /// @param value  Amount of sQPN to send
    function transfer(
        address to,
        uint256 value
    ) public override(IERC20, ERC20) returns (bool) {
        uint256 gonValue = value * _gonsPerFragment;

        _gonBalances[msg.sender] = _gonBalances[msg.sender] - gonValue;
        _gonBalances[to] = _gonBalances[to] + gonValue;

        emit Transfer(msg.sender, to, value);
        return true;
    }

    /// @notice       Transfer sQPN
    /// @param from   Address sending sQPN from
    /// @param to     Address sending sQPN to
    /// @param value  Amount of sQPN to send
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public override(IERC20, ERC20) returns (bool) {
        _allowedValue[from][msg.sender] =
            _allowedValue[from][msg.sender] -
            value;
        emit Approval(from, msg.sender, _allowedValue[from][msg.sender]);

        uint256 gonValue = gonsForBalance(value);
        _gonBalances[from] = _gonBalances[from] - gonValue;
        _gonBalances[to] = _gonBalances[to] + gonValue;

        emit Transfer(from, to, value);
        return true;
    }

    function approve(
        address spender,
        uint256 value
    ) public override(IERC20, ERC20) returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public override returns (bool) {
        _approve(
            msg.sender,
            spender,
            _allowedValue[msg.sender][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public override returns (bool) {
        uint256 oldValue = _allowedValue[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _approve(msg.sender, spender, 0);
        } else {
            _approve(msg.sender, spender, oldValue - subtractedValue);
        }
        return true;
    }

    /// INTERNAL FUNCTIONS ///

    function _approve(
        address owner,
        address spender,
        uint256 value
    ) internal virtual override {
        _allowedValue[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /// VIEW FUNCTIONS ///

    /// @notice       Returns balance of an address
    /// @param who    Address of who to get balance from
    function balanceOf(
        address who
    ) public view override(IERC20, ERC20) returns (uint256) {
        return _gonBalances[who] / _gonsPerFragment;
    }

    /// @notice        Returns calculation of gons for amount of sQPN
    /// @param amount  Amount of sQPN to calculate gons for
    function gonsForBalance(
        uint256 amount
    ) public view override returns (uint256) {
        return amount * _gonsPerFragment;
    }

    /// @notice      Returns calculation of balance for gons amount
    /// @param gons  Amount of gons to calculate sQPN for
    function balanceForGons(
        uint256 gons
    ) public view override returns (uint256) {
        return gons / _gonsPerFragment;
    }

    /// @notice  Returns sQPN circulating supply (Total Supply - Staking Contract Balance)
    function circulatingSupply() public view override returns (uint256) {
        return _totalSupply - balanceOf(stakingContract);
    }

    /// @notice  Returns current sQPN index
    function index() public view override returns (uint256) {
        return balanceForGons(INDEX);
    }

    function allowance(
        address owner_,
        address spender
    ) public view override(IERC20, ERC20) returns (uint256) {
        return _allowedValue[owner_][spender];
    }
}
