// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./AccessControlEnumerable.sol";
import "./ERC20Burnable.sol";
import "./ABDKMath64x64.sol";
import "./IUniswapPair.sol";
import "./IUniswapV2Router.sol";
import "./ArbSys.sol";
import "./IFuel.sol";
import "./IRefineries.sol";
import "./console.sol";

// General idea for debasing - show fragments in view functions, operate with underlying value internally
contract Fuel is Context, AccessControlEnumerable, ERC20Burnable, IFuel {
    using SafeMath for uint256;

    // ====== STORAGE ====== //

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 constant MAX_UINT = 2 ** 256 - 1;
    uint256 constant BASE_SCALING_FACTOR = 1e18;
    uint256 public scalingFactor = 1e18;

    uint256 public blocksPerEpoch;
    uint256 public lastBlockScale;

    // Compound ratio should be 0.0231% per epoch on arb for each 2310 blocks (around 10 min)
    uint256 public compoundRatio;

    IUniswapV2Router02 public router;
    IUniswapPair public lp;
    IRefineries public refineries;

    bool private shouldSyncLp = false;

    // denominator is 10000. tax 600 = 6.00%
    uint256 public buyTax = 600;
    uint256 public sellTax = 600;
    mapping(address => bool) public isExcludedFromFee;
    address prizePool;

    // ====== MODIFIERS ====== //

    // gas saving measure, used in non-view functions to update the time/block deltas
    // so large compound calculations aren't reached per ChocoScaling query.
    function updateScalingFactor(bool forceSyncLp) public {
        uint256 oldScalingFactor = scalingFactor;
        scalingFactor = getCurrentScalingFactor();
        if (oldScalingFactor != scalingFactor) {
            if (forceSyncLp) {
                lp.sync();
            } else {
                shouldSyncLp = true;
            }
            lastBlockScale = lastBlockScale + getDebaseEpochs() * blocksPerEpoch;
        }
    }

    // ====== CONSTRUCTOR ====== //

    constructor(
        string memory name,
        string memory symbol,
        uint256 _blocksPerEpoch,
        uint256 _compoundRatio,
        IUniswapV2Router02 _router,
        address _prizePool
    ) ERC20(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);

        blocksPerEpoch = _blocksPerEpoch;
        compoundRatio = _compoundRatio;
        router = _router;

        prizePool = _prizePool;

        // approve router once for max, saves on gas
        _approve(address(this), address(router), MAX_UINT);

        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[msg.sender] = true;
        // exclude router from fees to not charge fees on removing LP. It is not possible to exclude charging fees on adding LP tho
        isExcludedFromFee[address(router)] = true;

        _mint(msg.sender, fragmentToToken(2530000000000 * 1e18));
    }

    // ====== OVERRIDE parts of ERC20 to replace Transfer event, adjust balances and add custom logic ====== //

    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

    function balanceOf(address account) public view override(ERC20, IFuel) returns (uint256) {
        if (account == address(lp)) {
            return tokensToFragment(_balances[account]);
        }
        return tokensToFragmentAtCurrentScalingFactor(_balances[account]);
    }

    function totalSupply() public view virtual override returns (uint256) {
        return tokensToFragmentAtCurrentScalingFactor(_totalSupply);
    }

    function _transfer(address from, address to, uint256 amount) internal virtual override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (shouldSyncLp == true && from != address(lp)) {
            lp.sync();
            shouldSyncLp = false;
        }

        if (from == address(lp)) {
            // buy token / remove LP
            if (!isExcludedFromFee[to]) {
                uint256 taxAmount = (amount * buyTax) / 10000;
                _transfer(from, address(this), taxAmount);
                amount -= taxAmount;
            }
        } else if (to == address(lp)) {
            // sell token / add LP
            if (!isExcludedFromFee[from]) {
                uint256 taxAmount = (amount * sellTax) / 10000;
                _transfer(from, address(this), taxAmount);
                amount -= taxAmount;
            }
        } else {
            // transfer
        }

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, tokensToFragment(amount));

        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual override {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }

        emit Transfer(address(0), account, tokensToFragment(amount));

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual override {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), tokensToFragment(amount));

        _afterTokenTransfer(account, address(0), amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal override {
        if (address(refineries) != address(0) && !hasRole(DEFAULT_ADMIN_ROLE, tx.origin)) {
            require(refineries.survivedRefineries() > 1, "[FUEL] Only one refinery is alive, game is over!");
        }
    }

    // ====== VIEWS ====== //

    function getBlockNumber() public view returns (uint256) {
        return ArbSys(address(100)).arbBlockNumber();
    }

    function compoundDebase(uint256 principal, uint256 ratio, uint256 n) public pure returns (uint256) {
        return
            ABDKMath64x64.mulu(
                ABDKMath64x64.pow(ABDKMath64x64.sub(ABDKMath64x64.fromUInt(1), ABDKMath64x64.divu(ratio, 10 ** 18)), n),
                principal
            );
    }

    function balanceOfUnderlying(address account) public view returns (uint256) {
        return _balances[account];
    }

    function getDebaseEpochs() internal view returns (uint256) {
        if (lastBlockScale == 0 || lastBlockScale >= getBlockNumber()) {
            return 0;
        }
        return (getBlockNumber() - lastBlockScale) / blocksPerEpoch;
    }

    function getCurrentScalingFactor() public view returns (uint256) {
        uint256 debaseEpochs = getDebaseEpochs();
        if (debaseEpochs == 0) {
            return scalingFactor;
        }
        return scalingFactor.mul(compoundDebase(1e18, compoundRatio, debaseEpochs)).div(1e18);
    }

    function tokensToFragment(uint256 amount) public view returns (uint256) {
        return amount.mul(scalingFactor).div(BASE_SCALING_FACTOR);
    }

    function fragmentToToken(uint256 value) public view returns (uint256) {
        return value.mul(BASE_SCALING_FACTOR).div(scalingFactor);
    }

    function tokensToFragmentAtCurrentScalingFactor(uint256 amount) public view override returns (uint256) {
        return amount.mul(getCurrentScalingFactor()).div(BASE_SCALING_FACTOR);
    }

    function fragmentToTokenAtCurrentScalingFactor(uint256 value) public view override returns (uint256) {
        return value.mul(BASE_SCALING_FACTOR).div(getCurrentScalingFactor());
    }

    // ====== PUBLIC FUNCTIONS ====== //

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (from != address(lp)) {
            updateScalingFactor(false);
        }
        return super.transferFrom(from, to, fragmentToToken(amount));
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (msg.sender != address(lp)) {
            updateScalingFactor(false);
        }
        return super.transfer(to, fragmentToToken(amount));
    }

    function burn(uint256 amount) public override(ERC20Burnable, IFuel) {
        updateScalingFactor(false);
        _burn(msg.sender, fragmentToToken(amount));
    }

    function burnUnderlying(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    function transferUnderlying(address to, uint256 amount) public returns (bool) {
        return super.transfer(to, amount);
    }

    function approve(address spender, uint256 amount) public override(ERC20, IFuel) returns (bool) {
        updateScalingFactor(false);
        // prevent overflow
        uint256 tokensAmount = amount >= (MAX_UINT / BASE_SCALING_FACTOR) ? MAX_UINT : fragmentToToken(amount);
        _approve(msg.sender, spender, tokensAmount);
        return true;
    }

    receive() external payable {}

    // proxy function to bypass tax on adding LP
    function addLiquidity(uint256 fuelDesiredAmount) external payable {
        require(msg.value > 0 && fuelDesiredAmount > 0, "Zero amount");
        updateScalingFactor(false);

        _transfer(msg.sender, address(this), fragmentToToken(fuelDesiredAmount));

        (uint256 amountFuel, uint256 amountETH, ) = router.addLiquidityETH{value: msg.value}(
            address(this),
            fuelDesiredAmount,
            0,
            0,
            msg.sender,
            type(uint256).max
        );

        if (fuelDesiredAmount > amountFuel) {
            _transfer(address(this), msg.sender, fragmentToToken(fuelDesiredAmount - amountFuel));
        }
        if (msg.value > amountETH) {
            payable(msg.sender).transfer(msg.value - amountETH);
        }
    }

    // ====== INTERNAL FUNCTIONS ====== //

    // ====== ONLY MINTER ====== //

    /**
     * @notice Mints new tokens, increasing totalSupply the address balance.
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) returns (bool) {
        updateScalingFactor(false);
        _mint(to, fragmentToToken(amount));
        return true;
    }

    // ====== ONLY ADMIN ====== //

    function initializeRebasing() public onlyRole(DEFAULT_ADMIN_ROLE) {
        lastBlockScale = getBlockNumber();
    }

    function setRefineries(IRefineries _refineries) public onlyRole(DEFAULT_ADMIN_ROLE) {
        refineries = _refineries;
    }

    function setTheCompoundRatio(uint256 _compoundRatio) public onlyRole(DEFAULT_ADMIN_ROLE) {
        compoundRatio = _compoundRatio;
    }

    function setBlocksPerEpoch(uint256 _blocksPerEpoch) external onlyRole(DEFAULT_ADMIN_ROLE) {
        blocksPerEpoch = _blocksPerEpoch;
    }

    function setTaxes(uint256 _buyTax, uint256 _sellTax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        buyTax = _buyTax;
        sellTax = _sellTax;
    }

    function setLp(IUniswapPair _lp) public onlyRole(DEFAULT_ADMIN_ROLE) {
        lp = _lp;
    }

    function setIsExcludedFromFee(address _address, bool _isExcluded) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isExcludedFromFee[_address] = _isExcluded;
    }

    function sellTaxedTokens(uint256 tokenAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tokenAmount > 0, "[Fuel] Wrong token amount");

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of tokens
            path,
            address(this),
            block.timestamp
        );

        uint256 balance = address(this).balance;
        uint256 prizePoolPortion = (balance * 2) / 3;
        payable(prizePool).transfer(prizePoolPortion);
        payable(msg.sender).transfer(balance - prizePoolPortion);
    }

    function adminWithdraw(address token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function adminWithdrawETH() external onlyRole(DEFAULT_ADMIN_ROLE) {
        payable(msg.sender).transfer(address(this).balance);
    }
}

