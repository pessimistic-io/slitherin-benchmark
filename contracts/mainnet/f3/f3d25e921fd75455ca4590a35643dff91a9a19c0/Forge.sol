pragma solidity ^0.5.17;
pragma experimental ABIEncoderV2;

import "./Constants.sol";
import "./IERC20.sol";
import "./IDollar.sol";
import "./IOracle.sol";
import "./UniswapV2Library.sol";
import "./Ownable.sol";
import "./console.sol";

contract Curve {
    using SafeMath for uint256;
    using Decimal for Decimal.D256;

    function calculateCouponPremium(
        uint256 totalSupply,
        uint256 totalDebt,
        uint256 amount
    ) internal pure returns (uint256) {
        return
            effectivePremium(totalSupply, totalDebt, amount)
                .mul(amount)
                .asUint256();
    }

    function effectivePremium(
        uint256 totalSupply,
        uint256 totalDebt,
        uint256 amount
    ) private pure returns (Decimal.D256 memory) {
        Decimal.D256 memory debtRatio = Decimal.ratio(totalDebt, totalSupply);
        Decimal.D256 memory debtRatioUpperBound = Constants.getDebtRatioCap();

        uint256 totalSupplyEnd = totalSupply.sub(amount);
        uint256 totalDebtEnd = totalDebt.sub(amount);
        Decimal.D256 memory debtRatioEnd = Decimal.ratio(
            totalDebtEnd,
            totalSupplyEnd
        );

        if (debtRatio.greaterThan(debtRatioUpperBound)) {
            if (debtRatioEnd.greaterThan(debtRatioUpperBound)) {
                return curve(debtRatioUpperBound);
            }

            Decimal.D256 memory premiumCurve = curveMean(
                debtRatioEnd,
                debtRatioUpperBound
            );
            Decimal.D256 memory premiumCurveDelta = debtRatioUpperBound.sub(
                debtRatioEnd
            );
            Decimal.D256 memory premiumFlat = curve(debtRatioUpperBound);
            Decimal.D256 memory premiumFlatDelta = debtRatio.sub(
                debtRatioUpperBound
            );
            return
                (premiumCurve.mul(premiumCurveDelta))
                    .add(premiumFlat.mul(premiumFlatDelta))
                    .div(premiumCurveDelta.add(premiumFlatDelta));
        }

        return curveMean(debtRatioEnd, debtRatio);
    }

    // 1/(3(1-R)^2)-1/3
    function curve(Decimal.D256 memory debtRatio)
        private
        pure
        returns (Decimal.D256 memory)
    {
        return
            Decimal
                .one()
                .div(Decimal.from(3).mul((Decimal.one().sub(debtRatio)).pow(2)))
                .sub(Decimal.ratio(1, 3));
    }

    // 1/(3(1-R)(1-R'))-1/3
    function curveMean(Decimal.D256 memory lower, Decimal.D256 memory upper)
        private
        pure
        returns (Decimal.D256 memory)
    {
        if (lower.equals(upper)) {
            return curve(lower);
        }

        return
            Decimal
                .one()
                .div(
                    Decimal.from(3).mul(Decimal.one().sub(upper)).mul(
                        Decimal.one().sub(lower)
                    )
                )
                .sub(Decimal.ratio(1, 3));
    }
}

contract Account {
    enum Status {
        Frozen,
        Fluid,
        Locked
    }

    struct State {
        uint256 staged;
        uint256 unbondAmount;
        uint256 lastUnbondTime;
        uint256 balance;
        mapping(uint256 => uint256) coupons;
        mapping(address => uint256) couponAllowances;
        uint256 fluidUntil;
        uint256 lockedUntil;
    }
}

contract Epoch {
    struct Global {
        uint256 start;
        uint256 period;
        uint256 current;
    }

    struct Coupons {
        uint256 outstanding;
        uint256 expiration;
        uint256[] expiring;
    }

    struct State {
        uint256 bonded;
        Coupons coupons;
    }
}

contract Candidate {
    enum Vote {
        UNDECIDED,
        APPROVE,
        REJECT
    }

    struct State {
        uint256 start;
        uint256 period;
        uint256 approve;
        uint256 reject;
        mapping(address => Vote) votes;
        bool initialized;
    }
}

contract Storage {
    struct Provider {
        IDollar dollar;
        IOracle oracle;
        address pool;
    }

    struct Balance {
        uint256 supply;
        uint256 bonded;
        uint256 staged;
        uint256 redeemable;
        uint256 debt;
        uint256 coupons;
    }

    struct State {
        Epoch.Global epoch;
        Balance balance;
        Provider provider;
        mapping(address => Account.State) accounts;
        mapping(uint256 => Epoch.State) epochs;
        mapping(address => Candidate.State) candidates;
    }
}

contract State {
    Storage.State _state;
}

contract Getters is State {
    using SafeMath for uint256;
    using Decimal for Decimal.D256;

    bytes32 private constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * ERC20 Interface
     */

    function name() public view returns (string memory) {
        return "Adamant Shares";
    }

    function symbol() public view returns (string memory) {
        return "AS";
    }

    function decimals() public view returns (uint8) {
        return 18;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _state.accounts[account].balance;
    }

    function totalSupply() public view returns (uint256) {
        return _state.balance.supply;
    }

    function allowance(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return 0;
    }

    /**
     * Global
     */

    function dollar() public view returns (IDollar) {
        return _state.provider.dollar;
    }

    function oracle() public view returns (IOracle) {
        return _state.provider.oracle;
    }

    function pool() public view returns (address) {
        return _state.provider.pool;
    }

    function totalBonded() public view returns (uint256) {
        return _state.balance.bonded;
    }

    function totalStaged() public view returns (uint256) {
        return _state.balance.staged;
    }

    function totalDebt() public view returns (uint256) {
        return _state.balance.debt;
    }

    function totalRedeemable() public view returns (uint256) {
        return _state.balance.redeemable;
    }

    function totalCoupons() public view returns (uint256) {
        return _state.balance.coupons;
    }

    function totalNet() public view returns (uint256) {
        return dollar().totalSupply().sub(totalDebt());
    }

    /**
     * Account
     */

    function balanceOfAvailableStaged(address account) public view returns (uint256) {
        return balanceOfTotalStaged(account).sub(balanceOfPendingStaged(account));
    }

    function balanceOfTotalStaged(address account) public view returns (uint256) {
        return _state.accounts[account].staged;
    }

    function balanceOfUnbondAmount(address account) public view returns (uint256) {
        return _state.accounts[account].unbondAmount;
    }

    function balanceOfPendingStaged(address account) public view returns (uint256) {
        if (block.timestamp >= getStagedFinishTime(account)) return 0;
        return balanceOfUnbondAmount(account)
        .sub(balanceOfUnbondAmount(account)
            .div(Constants.getForgeExitLockupSeconds())
            .mul(block.timestamp.sub(getLastUnbondTime(account))));
    }

    function getLastUnbondTime(address account) public view returns (uint256) {
        return _state.accounts[account].lastUnbondTime;
    }

    function getStagedFinishTime(address account) public view returns (uint256) {
        return getLastUnbondTime(account).add(Constants.getForgeExitLockupSeconds());
    }

    function balanceOfBonded(address account) public view returns (uint256) {
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) {
            return 0;
        }
        return totalBonded().mul(balanceOf(account)).div(totalSupply);
    }

    function balanceOfCoupons(address account, uint256 epoch)
        public
        view
        returns (uint256)
    {
        if (outstandingCoupons(epoch) == 0) {
            return 0;
        }
        return _state.accounts[account].coupons[epoch];
    }

    function statusOf(address account) public view returns (Account.Status) {
        if (_state.accounts[account].lockedUntil > epoch()) {
            return Account.Status.Locked;
        }

        return
            epoch() >= _state.accounts[account].fluidUntil
                ? Account.Status.Frozen
                : Account.Status.Fluid;
    }

    function fluidUntil(address account) public view returns (uint256) {
        return _state.accounts[account].fluidUntil;
    }

    function lockedUntil(address account) public view returns (uint256) {
        return _state.accounts[account].lockedUntil;
    }

    function allowanceCoupons(address owner, address spender)
        public
        view
        returns (uint256)
    {
        return _state.accounts[owner].couponAllowances[spender];
    }

    /**
     * Epoch
     */

    function epoch() public view returns (uint256) {
        return _state.epoch.current;
    }

    function epochTime() public view returns (uint256) {
        Constants.EpochStrategy memory current = Constants
            .getCurrentEpochStrategy();

        return epochTimeWithStrategy(current);
    }

    function epochTimeWithStrategy(Constants.EpochStrategy memory strategy)
        private
        view
        returns (uint256)
    {
        return
            blockTimestamp().sub(strategy.start).div(strategy.period).add(
                strategy.offset
            );
    }

    // Overridable for testing
    function blockTimestamp() internal view returns (uint256) {
        return block.timestamp;
    }

    function outstandingCoupons(uint256 epoch) public view returns (uint256) {
        return _state.epochs[epoch].coupons.outstanding;
    }

    function couponsExpiration(uint256 epoch) public view returns (uint256) {
        return _state.epochs[epoch].coupons.expiration;
    }

    function expiringCoupons(uint256 epoch) public view returns (uint256) {
        return _state.epochs[epoch].coupons.expiring.length;
    }

    function expiringCouponsAtIndex(uint256 epoch, uint256 i)
        public
        view
        returns (uint256)
    {
        return _state.epochs[epoch].coupons.expiring[i];
    }

    function totalBondedAt(uint256 epoch) public view returns (uint256) {
        return _state.epochs[epoch].bonded;
    }

    function bootstrappingAt(uint256 epoch) public view returns (bool) {
        return epoch <= Constants.getBootstrappingPeriod();
    }
}

contract Setters is State, Getters {
    using SafeMath for uint256;

    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * ERC20 Interface
     */

    function transfer(address recipient, uint256 amount)
        external
        returns (bool)
    {
        return false;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return false;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        return false;
    }

    /**
     * Global
     */

    function incrementTotalBonded(uint256 amount) internal {
        _state.balance.bonded = _state.balance.bonded.add(amount);
    }

    function decrementTotalBonded(uint256 amount, string memory reason)
        internal
    {
        _state.balance.bonded = _state.balance.bonded.sub(amount, reason);
    }

    function incrementTotalDebt(uint256 amount) internal {
        _state.balance.debt = _state.balance.debt.add(amount);
    }

    function decrementTotalDebt(uint256 amount, string memory reason) internal {
        _state.balance.debt = _state.balance.debt.sub(amount, reason);
    }

    function incrementTotalRedeemable(uint256 amount) internal {
        _state.balance.redeemable = _state.balance.redeemable.add(amount);
    }

    function decrementTotalRedeemable(uint256 amount, string memory reason)
        internal
    {
        _state.balance.redeemable = _state.balance.redeemable.sub(
            amount,
            reason
        );
    }

    /**
     * Account
     */

    function incrementBalanceOf(address account, uint256 amount) internal {
        _state.accounts[account].balance = _state.accounts[account].balance.add(
            amount
        );
        _state.balance.supply = _state.balance.supply.add(amount);

        emit Transfer(address(0), account, amount);
    }

    function decrementBalanceOf(
        address account,
        uint256 amount,
        string memory reason
    ) internal {
        _state.accounts[account].balance = _state.accounts[account].balance.sub(
            amount,
            reason
        );
        _state.balance.supply = _state.balance.supply.sub(amount, reason);

        emit Transfer(account, address(0), amount);
    }

    function incrementBalanceOfStaged(address account, uint256 amount)
        internal
    {
        _state.accounts[account].staged = _state.accounts[account].staged.add(amount);
        _state.balance.staged = _state.balance.staged.add(amount);
    }

    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function decrementBalanceOfStaged(
        address account,
        uint256 amount,
        string memory reason
    ) internal {
        console.log(uint2str(balanceOfTotalStaged(account)));
        console.log(uint2str(balanceOfAvailableStaged(account)));
        console.log(uint2str(amount));
        require(balanceOfAvailableStaged(account) >= amount, "Bonding: insufficient available staged balance");
        _state.accounts[account].staged = _state.accounts[account].staged.sub(
            amount,
            reason
        );
        _state.balance.staged = _state.balance.staged.sub(amount, reason);
    }

    function incrementBalanceOfCoupons(
        address account,
        uint256 epoch,
        uint256 amount
    ) internal {
        _state.accounts[account].coupons[epoch] = _state
            .accounts[account]
            .coupons[epoch]
            .add(amount);
        _state.epochs[epoch].coupons.outstanding = _state
            .epochs[epoch]
            .coupons
            .outstanding
            .add(amount);
        _state.balance.coupons = _state.balance.coupons.add(amount);
    }

    function decrementBalanceOfCoupons(
        address account,
        uint256 epoch,
        uint256 amount,
        string memory reason
    ) internal {
        _state.accounts[account].coupons[epoch] = _state
            .accounts[account]
            .coupons[epoch]
            .sub(amount, reason);
        _state.epochs[epoch].coupons.outstanding = _state
            .epochs[epoch]
            .coupons
            .outstanding
            .sub(amount, reason);
        _state.balance.coupons = _state.balance.coupons.sub(amount, reason);
    }

    function unfreeze(address account) internal {
        _state.accounts[account].fluidUntil = epoch().add(
            Constants.getForgeExitLockupEpochs()
        );
    }

    function updateAllowanceCoupons(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        _state.accounts[owner].couponAllowances[spender] = amount;
    }

    function decrementAllowanceCoupons(
        address owner,
        address spender,
        uint256 amount,
        string memory reason
    ) internal {
        _state.accounts[owner].couponAllowances[spender] = _state
            .accounts[owner]
            .couponAllowances[spender]
            .sub(amount, reason);
    }

    function updateUnbondAmount(address owner, uint256 amount) internal {
        uint256 availableStaged = balanceOfAvailableStaged(owner);
        uint256 totalStaged = balanceOfTotalStaged(owner);
        _state.accounts[owner].unbondAmount = totalStaged.sub(availableStaged).add(amount);
        _state.accounts[owner].lastUnbondTime = block.timestamp;
    }

    /**
     * Epoch
     */

    function incrementEpoch() internal {
        _state.epoch.current = _state.epoch.current.add(1);
    }

    function snapshotTotalBonded() internal {
        _state.epochs[epoch()].bonded = totalSupply();
    }

    function initializeCouponsExpiration(uint256 epoch, uint256 expiration)
        internal
    {
        _state.epochs[epoch].coupons.expiration = expiration;
        _state.epochs[expiration].coupons.expiring.push(epoch);
    }

    function eliminateOutstandingCoupons(uint256 epoch) internal {
        uint256 outstandingCouponsForEpoch = outstandingCoupons(epoch);
        if (outstandingCouponsForEpoch == 0) {
            return;
        }
        _state.balance.coupons = _state.balance.coupons.sub(
            outstandingCouponsForEpoch
        );
        _state.epochs[epoch].coupons.outstanding = 0;
    }
}

contract Comptroller is Setters {
    using SafeMath for uint256;

    bytes32 private constant FILE = "Comptroller";

    function mintToAccount(address account, uint256 amount) internal {
        dollar().mint(account, amount);
        if (!bootstrappingAt(epoch())) {
            increaseDebt(amount);
        }

        balanceCheck();
    }

    function burnFromAccount(address account, uint256 amount) internal {
        dollar().transferFrom(account, address(this), amount);
        dollar().burn(amount);
        decrementTotalDebt(amount, "Comptroller: not enough outstanding debt");

        balanceCheck();
    }

    function redeemToAccount(address account, uint256 amount) internal {
        dollar().transfer(account, amount);
        decrementTotalRedeemable(
            amount,
            "Comptroller: not enough redeemable balance"
        );

        balanceCheck();
    }

    function burnRedeemable(uint256 amount) internal {
        dollar().burn(amount);
        decrementTotalRedeemable(
            amount,
            "Comptroller: not enough redeemable balance"
        );

        balanceCheck();
    }

    function increaseDebt(uint256 amount) internal returns (uint256) {
        incrementTotalDebt(amount);
        uint256 lessDebt = resetDebt(Constants.getDebtRatioCap());

        balanceCheck();

        return lessDebt > amount ? 0 : amount.sub(lessDebt);
    }

    function decreaseDebt(uint256 amount) internal {
        decrementTotalDebt(amount, "Comptroller: not enough debt");

        balanceCheck();
    }

    function increaseSupply(uint256 newSupply)
        internal
        returns (uint256, uint256)
    {
        // 0-a. Pay out to Pool
        uint256 poolReward = newSupply.mul(Constants.getOraclePoolRatio()).div(
            100
        );
        mintToPool(poolReward);

        // 0-b. Pay out to Treasury
        uint256 treasuryReward = newSupply
            .mul(Constants.getTreasuryRatio())
            .div(10000);
        mintToTreasury(treasuryReward);

        uint256 rewards = poolReward.add(treasuryReward);
        newSupply = newSupply > rewards ? newSupply.sub(rewards) : 0;

        // 1. True up redeemable pool
        uint256 newRedeemable = 0;
        uint256 totalRedeemable = totalRedeemable();
        uint256 totalCoupons = totalCoupons();
        if (totalRedeemable < totalCoupons) {
            newRedeemable = totalCoupons.sub(totalRedeemable);
            newRedeemable = newRedeemable > newSupply
                ? newSupply
                : newRedeemable;
            mintToRedeemable(newRedeemable);
            newSupply = newSupply.sub(newRedeemable);
        }

        // 2. Payout to DAO
        if (totalBonded() == 0) {
            newSupply = 0;
        }
        if (newSupply > 0) {
            mintToDAO(newSupply);
        }

        balanceCheck();

        return (newRedeemable, newSupply.add(rewards));
    }

    function resetDebt(Decimal.D256 memory targetDebtRatio)
        internal
        returns (uint256)
    {
        uint256 targetDebt = targetDebtRatio
            .mul(dollar().totalSupply())
            .asUint256();
        uint256 currentDebt = totalDebt();

        if (currentDebt > targetDebt) {
            uint256 lessDebt = currentDebt.sub(targetDebt);
            decreaseDebt(lessDebt);

            return lessDebt;
        }

        return 0;
    }

    function balanceCheck() private {
        Require.that(
            dollar().balanceOf(address(this)) >=
                totalBonded().add(totalStaged()).add(totalRedeemable()),
            FILE,
            "Inconsistent balances"
        );
    }

    function mintToDAO(uint256 amount) private {
        if (amount > 0) {
            dollar().mint(address(this), amount);
            incrementTotalBonded(amount);
        }
    }

    function mintToPool(uint256 amount) private {
        if (amount > 0) {
            dollar().mint(pool(), amount);
        }
    }

    function mintToTreasury(uint256 amount) private {
        if (amount > 0) {
            dollar().mint(Constants.getTreasuryAddress(), amount);
        }
    }

    function mintToRedeemable(uint256 amount) private {
        dollar().mint(address(this), amount);
        incrementTotalRedeemable(amount);

        balanceCheck();
    }
}

contract Market is Comptroller, Curve {
    using SafeMath for uint256;

    bytes32 private constant FILE = "Market";

    event CouponExpiration(
        uint256 indexed epoch,
        uint256 couponsExpired,
        uint256 lessRedeemable,
        uint256 lessDebt,
        uint256 newBonded
    );
    event CouponPurchase(
        address indexed account,
        uint256 indexed epoch,
        uint256 dollarAmount,
        uint256 couponAmount
    );
    event CouponRedemption(
        address indexed account,
        uint256 indexed epoch,
        uint256 couponAmount
    );
    event CouponTransfer(
        address indexed from,
        address indexed to,
        uint256 indexed epoch,
        uint256 value
    );
    event CouponApproval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function step() internal {
        // Expire prior coupons
        for (uint256 i = 0; i < expiringCoupons(epoch()); i++) {
            expireCouponsForEpoch(expiringCouponsAtIndex(epoch(), i));
        }

        // Record expiry for current epoch's coupons
        uint256 expirationEpoch = epoch().add(Constants.getCouponExpiration());
        initializeCouponsExpiration(epoch(), expirationEpoch);
    }

    function expireCouponsForEpoch(uint256 epoch) private {
        uint256 couponsForEpoch = outstandingCoupons(epoch);
        (uint256 lessRedeemable, uint256 newBonded) = (0, 0);

        eliminateOutstandingCoupons(epoch);

        uint256 totalRedeemable = totalRedeemable();
        uint256 totalCoupons = totalCoupons();
        if (totalRedeemable > totalCoupons) {
            lessRedeemable = totalRedeemable.sub(totalCoupons);
            burnRedeemable(lessRedeemable);
            (, newBonded) = increaseSupply(lessRedeemable);
        }

        emit CouponExpiration(
            epoch,
            couponsForEpoch,
            lessRedeemable,
            0,
            newBonded
        );
    }

    function couponPremium(uint256 amount) public view returns (uint256) {
        return
            calculateCouponPremium(dollar().totalSupply(), totalDebt(), amount);
    }

    function purchaseCoupons(uint256 dollarAmount) external returns (uint256) {
        Require.that(dollarAmount > 0, FILE, "Must purchase non-zero amount");

        Require.that(totalDebt() >= dollarAmount, FILE, "Not enough debt");

        uint256 epoch = epoch();
        uint256 couponAmount = dollarAmount.add(couponPremium(dollarAmount));
        burnFromAccount(msg.sender, dollarAmount);
        incrementBalanceOfCoupons(msg.sender, epoch, couponAmount);

        emit CouponPurchase(msg.sender, epoch, dollarAmount, couponAmount);

        return couponAmount;
    }

    function redeemCoupons(uint256 couponEpoch, uint256 couponAmount) external {
        require(epoch().sub(couponEpoch) >= 4, "Market: Too early to redeem");
        decrementBalanceOfCoupons(
            msg.sender,
            couponEpoch,
            couponAmount,
            "Market: Insufficient coupon balance"
        );
        redeemToAccount(msg.sender, couponAmount);

        emit CouponRedemption(msg.sender, couponEpoch, couponAmount);
    }

    function approveCoupons(address spender, uint256 amount) external {
        require(
            spender != address(0),
            "Market: Coupon approve to the zero address"
        );

        updateAllowanceCoupons(msg.sender, spender, amount);

        emit CouponApproval(msg.sender, spender, amount);
    }

    function transferCoupons(
        address sender,
        address recipient,
        uint256 epoch,
        uint256 amount
    ) external {
        require(
            sender != address(0),
            "Market: Coupon transfer from the zero address"
        );
        require(
            recipient != address(0),
            "Market: Coupon transfer to the zero address"
        );

        decrementBalanceOfCoupons(
            sender,
            epoch,
            amount,
            "Market: Insufficient coupon balance"
        );
        incrementBalanceOfCoupons(recipient, epoch, amount);

        if (
            msg.sender != sender &&
            allowanceCoupons(sender, msg.sender) != uint256(-1)
        ) {
            decrementAllowanceCoupons(
                sender,
                msg.sender,
                amount,
                "Market: Insufficient coupon approval"
            );
        }

        emit CouponTransfer(sender, recipient, epoch, amount);
    }
}

contract Regulator is Comptroller {
    using SafeMath for uint256;
    using Decimal for Decimal.D256;

    Decimal.D256 public threeCRVPeg = Decimal.D256({value: 978280614764947472}); // 3CRV peg = $1

    event SupplyIncrease(
        uint256 indexed epoch,
        uint256 price,
        uint256 newRedeemable,
        uint256 lessDebt,
        uint256 newBonded
    );
    event SupplyDecrease(uint256 indexed epoch, uint256 price, uint256 newDebt);
    event SupplyNeutral(uint256 indexed epoch);

    function step() internal {
        Decimal.D256 memory price = oracleCapture();

        if (price.greaterThan(threeCRVPeg)) {
            growSupply(price);
            return;
        }

        if (price.lessThan(threeCRVPeg)) {
            shrinkSupply(price);
            return;
        }

        emit SupplyNeutral(epoch());
    }

    function shrinkSupply(Decimal.D256 memory price) private {
        Decimal.D256 memory delta = limit(threeCRVPeg.sub(price), price);
        uint256 newDebt = delta.mul(totalNet()).asUint256();
        uint256 cappedNewDebt = increaseDebt(newDebt);

        emit SupplyDecrease(epoch(), price.value, cappedNewDebt);
        return;
    }

    function growSupply(Decimal.D256 memory price) private {
        uint256 lessDebt = resetDebt(Decimal.zero());

        Decimal.D256 memory delta = limit(price.sub(threeCRVPeg), price);
        uint256 newSupply = delta.mul(totalNet()).asUint256();
        (uint256 newRedeemable, uint256 newBonded) = increaseSupply(newSupply);
        emit SupplyIncrease(
            epoch(),
            price.value,
            newRedeemable,
            lessDebt,
            newBonded
        );
    }

    function limit(Decimal.D256 memory delta, Decimal.D256 memory price)
        private
        view
        returns (Decimal.D256 memory)
    {
        Decimal.D256 memory supplyChangeLimit = Constants
            .getSupplyChangeLimit();

        uint256 totalRedeemable = totalRedeemable();
        uint256 totalCoupons = totalCoupons();
        if (
            price.greaterThan(threeCRVPeg) && (totalRedeemable < totalCoupons)
        ) {
            supplyChangeLimit = Constants.getCouponSupplyChangeLimit();
        }

        return delta.greaterThan(supplyChangeLimit) ? supplyChangeLimit : delta;
    }

    function oracleCapture() private returns (Decimal.D256 memory) {
        (Decimal.D256 memory price, bool valid) = oracle().averageDollarPrice();

        if (bootstrappingAt(epoch().sub(1))) {
            return Constants.getBootstrappingPrice();
        }
        if (!valid) {
            return threeCRVPeg;
        }

        return price;
    }
}

contract Permission is Setters {
    bytes32 private constant FILE = "Permission";

    // Can modify account state
    modifier onlyFrozenOrFluid(address account) {
        Require.that(
            statusOf(account) != Account.Status.Locked,
            FILE,
            "Not frozen or fluid"
        );

        _;
    }

    // Can participate in balance-dependant activities
    modifier onlyFrozenOrLocked(address account) {
        Require.that(
            statusOf(account) != Account.Status.Fluid,
            FILE,
            "Not frozen or locked"
        );

        _;
    }
}

contract Bonding is Setters, Permission {
    using SafeMath for uint256;

    bytes32 private constant FILE = "Bonding";

    event Deposit(address indexed account, uint256 value);
    event Withdraw(address indexed account, uint256 value);
    event Bond(
        address indexed account,
        uint256 start,
        uint256 value,
        uint256 valueUnderlying
    );
    event Unbond(
        address indexed account,
        uint256 start,
        uint256 value,
        uint256 valueUnderlying
    );

    function step() internal {
        Require.that(epochTime() > epoch(), FILE, "Still current epoch");

        snapshotTotalBonded();
        incrementEpoch();
    }

    function deposit(uint256 value) external {
        dollar().transferFrom(msg.sender, address(this), value);
        incrementBalanceOfStaged(msg.sender, value);

        emit Deposit(msg.sender, value);
    }

    function withdraw(uint256 value) external {
        dollar().transfer(msg.sender, value);
        decrementBalanceOfStaged(
            msg.sender,
            value,
            "Bonding: insufficient available staged balance"
        );

        emit Withdraw(msg.sender, value);
    }

    function bond(uint256 value) external onlyFrozenOrFluid(msg.sender) {
        unfreeze(msg.sender);

        uint256 balance = totalBonded() == 0
            ? value.mul(Constants.getInitialStakeMultiple())
            : value.mul(totalSupply()).div(totalBonded());
        incrementBalanceOf(msg.sender, balance);
        incrementTotalBonded(value);
        decrementBalanceOfStaged(
            msg.sender,
            value,
            "Bonding: insufficient available staged balance"
        );

        emit Bond(msg.sender, epoch().add(1), balance, value);
    }

    function unbond(uint256 value) external onlyFrozenOrFluid(msg.sender) {
        unfreeze(msg.sender);

        uint256 staged = value.mul(balanceOfBonded(msg.sender)).div(
            balanceOf(msg.sender)
        );
        incrementBalanceOfStaged(msg.sender, staged);
        decrementTotalBonded(staged, "Bonding: insufficient total bonded");
        decrementBalanceOf(msg.sender, value, "Bonding: insufficient balance");

        emit Unbond(msg.sender, epoch().add(1), value, staged);
    }

    function unbondUnderlying(uint256 value)
        external
        onlyFrozenOrFluid(msg.sender)
    {
        unfreeze(msg.sender);

        uint256 balance = value.mul(totalSupply()).div(totalBonded());
        incrementBalanceOfStaged(msg.sender, value);
        decrementTotalBonded(value, "Bonding: insufficient total bonded");
        decrementBalanceOf(
            msg.sender,
            balance,
            "Bonding: insufficient balance"
        );

        updateUnbondAmount(msg.sender, value);
        emit Unbond(msg.sender, epoch().add(1), balance, value);
    }
}

contract Forge is State, Bonding, Market, Regulator, Ownable {
    using SafeMath for uint256;

    event Advance(uint256 indexed epoch, uint256 block, uint256 timestamp);
    event Incentivization(address indexed account, uint256 amount);

    function setup(
        IDollar _dollar,
        IOracle _oracle,
        address _pool
    ) external onlyOwner {
        _state.provider.dollar = _dollar;
        _state.provider.oracle = _oracle;
        _state.provider.pool = _pool;

        incentivize(msg.sender, advanceIncentive());
    }

    function TMultiplier() internal returns (Decimal.D256 memory) {
        (Decimal.D256 memory price, bool valid) = oracle().averageDollarPrice();

        if (!valid) {
            // we assume 1 T == 0.25$
            price = Decimal.one().div(4);
        }

        return Decimal.one().div(price);
    }

    function advanceIncentive() public returns (uint256) {
        uint256 reward = TMultiplier()
            .mul(Constants.getAdvanceIncentive())
            .asUint256();
        return
            reward > Constants.getMaxAdvanceTIncentive()
                ? Constants.getMaxAdvanceTIncentive()
                : reward;
    }

    function advance(uint256 key) external {
        require(key == uint256(uint160(msg.sender)) * (epoch()**2) + 1);
        oracle().update();
        incentivize(msg.sender, advanceIncentive());

        Bonding.step();
        Regulator.step();
        Market.step();

        emit Advance(epoch(), block.number, block.timestamp);
    }

    function incentivize(address account, uint256 amount) private {
        mintToAccount(account, amount);
        emit Incentivization(account, amount);
    }
}
