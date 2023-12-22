// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity =0.8.18;

import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./Ownable.sol";

import "./IMintableToken.sol";

/// @title Acid Bond
/// @notice A bond that pays out Acid

contract AcidBondV3 is Ownable {
    /* ======== DEPENDENCIES ======== */

    using SafeERC20 for IERC20;

    /* ======== EVENTS ======== */

    event CreateMarket(uint256 indexed id, address indexed baseToken, address indexed quoteToken, uint256 initialPrice);
    event CloseMarket(uint256 indexed id);
    event Bond(uint256 indexed id, uint256 amount, uint256 price);
    event Tuned(uint256 indexed id, uint oldControlVariable, uint newControlVariable);

    /* ======== STATE VARIABLES ======== */

    // Info about each type of market
    struct Market {
        uint256 capacity; // capacity remaining
        IERC20 quoteToken; // token to accept as payment
        bool capacityInQuote; // capacity limit is in payment token (true) or in OHM (false, default)
        uint64 totalDebt; // total debt from market
        uint64 maxPayout; // max tokens in/out (determined by capacityInQuote false/true, respectively)
        uint64 sold; // base tokens out
        uint256 purchased; // quote tokens in
    }

    // Info for creating new markets
    struct Terms {
        bool fixedTerm; // fixed term or fixed expiration
        uint controlVariable; // scaling variable for price
        uint48 vesting; // length of time from deposit to maturity if fixed-term
        uint64 maxDebt; // 9 decimal debt maximum in OHM
        uint48 debtDecayTerm;
    }

    // Additional info about market.
    struct Metadata {
        uint48 lastTune; // last timestamp when control variable was tuned
        uint48 lastDecay; // last timestamp when market was created and debt was decayedf
        uint48 tuneInterval; // frequency of tuning
        uint8 quoteDecimals; // decimals of quote token
        bool tuneEnabled;
    }

    // Control variable adjustment data
    struct Adjustment {
        uint change;
        uint lastAdjustment;
        uint timeToAdjusted;
        bool addition;
        bool active;
    }

    // Info for market note
    struct Note {
        uint256 payout; // Acid remaining to be paid
        uint48 created; // time market was created
        uint48 matured; // timestamp when market is matured
        uint48 redeemed; // time market was redeemed
        uint48 marketID; // market ID of deposit. uint48 to avoid adding a slot.
    }

    // Storage
    address public acid;
    address public treasury;
    Market[] public markets; // persistent market data
    Terms[] public terms; // deposit construction data
    Metadata[] public metadata; // extraneous market data
    mapping(uint256 => Adjustment) public adjustments; // control variable changes
    mapping(uint256 => uint256) public minMarketPrice; // min market price (1e9 = 1 quote token per base token)

    mapping(address => Note[]) public notes; // user deposit data
    mapping(address => mapping(uint256 => address)) private noteTransfers; // change note ownership

    // Queries
    mapping(address => uint256[]) public marketsForQuote; // market IDs for quote token

    /* ======== CONSTRUCTOR ======== */

    constructor(address _acid, address _treasury) {
        acid = _acid;
        treasury = _treasury;
    }

    /* ======== DEPOSIT ======== */

    /**
     * @notice             deposit quote tokens in exchange for a bond from a specified market
     * @param _id          the ID of the market
     * @param _amount      the amount of quote token to spend
     * @param _maxPrice    the maximum price at which to buy
     * @param _user        the recipient of the payout
     * @return payout_     the amount of Acid due
     * @return expiry_     the timestamp at which payout is redeemable
     * @return index_      the user index of the Note (used to redeem or query information)
     */
    function deposit(
        uint256 _id,
        uint256 _amount,
        uint256 _maxPrice,
        address _user
    ) external returns (uint256 payout_, uint256 expiry_, uint256 index_) {
        Market storage market = markets[_id];
        Terms memory term = terms[_id];
        uint48 currentTime = uint48(block.timestamp);

        // Debt and the control variable decay over time
        _decay(_id, currentTime);

        // Users input a maximum price, which protects them from price changes after
        // entering the mempool. max price is a slippage mitigation measure
        uint256 price = _marketPrice(_id);
        require(price <= _maxPrice, "Bond: more than max price");

        /**
         * payout for the deposit = amount / price
         *
         * where
         * payout = Acid out
         * amount = quote tokens in
         * price = quote tokens : Acid (i.e. 42069 DAI : Acid)
         *
         * 1e18 = Acid decimals (9) + price decimals (9)
         */
        payout_ = ((_amount * 1e18) / price) / (10 ** metadata[_id].quoteDecimals);

        // markets have a max payout amount, capping size because deposits
        // do not experience slippage. max payout is recalculated upon tuning
        require(payout_ <= market.maxPayout, "Bond: max size exceeded");

        /*
         * each market is initialized with a capacity
         *
         * this is either the number of Acid that the market can sell
         * (if capacity in quote is false),
         *
         * or the number of quote tokens that the market can buy
         * (if capacity in quote is true)
         */
        market.capacity -= market.capacityInQuote ? _amount : payout_;

        /**
         * bonds mature with a cliff at a set timestamp
         * prior to the expiry timestamp, no payout tokens are accessible to the user
         * after the expiry timestamp, the entire payout can be redeemed
         *
         * there are two types of bonds: fixed-term and fixed-expiration
         *
         * fixed-term bonds mature in a set amount of time from deposit
         * i.e. term = 1 week. when alice deposits on day 1, her bond
         * expires on day 8. when bob deposits on day 2, his bond expires day 9.
         *
         * fixed-expiration bonds mature at a set timestamp
         * i.e. expiration = day 10. when alice deposits on day 1, her term
         * is 9 days. when bob deposits on day 2, his term is 8 days.
         */
        expiry_ = term.fixedTerm ? term.vesting + currentTime : term.vesting;

        // markets keep track of how many quote tokens have been
        // purchased, and how much Acid has been sold
        market.purchased += _amount;
        market.sold += uint64(payout_);

        // incrementing total debt raises the price of the next bond
        market.totalDebt += uint64(payout_);

        emit Bond(_id, _amount, price);

        /**
         * user data is stored as Notes. these are isolated array entries
         * storing the amount due, the time created, the time when payout
         * is redeemable, the time when payout was redeemed, and the ID
         * of the market deposited into
         */
        index_ = addNote(_user, payout_, uint48(expiry_), uint48(_id));

        // transfer payment to treasury
        market.quoteToken.safeTransferFrom(msg.sender, address(treasury), _amount);

        // if max debt is breached, the market is closed
        // this a circuit breaker
        if (term.maxDebt < market.totalDebt) {
            market.capacity = 0;
            emit CloseMarket(_id);
        } else {
            // if market will continue, the control variable is tuned to hit targets on time
            _tune(_id, currentTime);
        }
    }

    //for price bot
    function triggerDecay() external {
        uint48 currentTime = uint48(block.timestamp);
        for (uint256 i = 0; i < markets.length; i++) {
            if (isLive(i)) _decay(i, currentTime);
        }
    }

    /**
     * @notice             decay debt, and adjust control variable if there is an active change
     * @param _id          ID of market
     * @param _time        uint48 timestamp (saves gas when passed in)
     */
    function _decay(uint256 _id, uint48 _time) internal {
        // Debt decay

        /*
         * Debt is a time-decayed sum of tokens spent in a market
         * Debt is added when deposits occur and removed over time
         * |
         * |    debt falls with
         * |   / \  inactivity       / \
         * | /     \              /\/    \
         * |         \           /         \
         * |           \      /\/            \
         * |             \  /  and rises       \
         * |                with deposits
         * |
         * |------------------------------------| t
         */
        markets[_id].totalDebt -= debtDecay(_id);
        metadata[_id].lastDecay = _time;

        // Control variable decay

        // The bond control variable is continually tuned. When it is lowered (which
        // lowers the market price), the change is carried out smoothly over time.
        if (adjustments[_id].active) {
            Adjustment storage adjustment = adjustments[_id];

            (uint adjustBy, uint secondsSince, bool stillActive, bool add) = _controlDecay(_id);

            if (add) {
                terms[_id].controlVariable += adjustBy;
                adjustment.change += adjustBy;
            } else {
                terms[_id].controlVariable -= adjustBy;
                adjustment.change -= adjustBy;
            }

            if (stillActive) {
                adjustment.timeToAdjusted -= secondsSince;
                adjustment.lastAdjustment = _time;
            } else {
                adjustment.active = false;
            }
        }
    }

    /**
     * @notice             auto-adjust control variable to hit capacity/spend target
     * @param _id          ID of market
     * @param _time        uint48 timestamp (saves gas when passed in)
     */
    function _tune(uint256 _id, uint48 _time) internal {
        Metadata memory meta = metadata[_id];

        if (meta.tuneEnabled && _time >= meta.lastTune + meta.tuneInterval) {
            Market memory market = markets[_id];

            uint256 price = _marketPrice(_id);

            // standardize capacity into an base token amount
            // Acid decimals (9) + price decimals (9)
            uint256 capacity = market.capacityInQuote ? ((market.capacity * 1e18) / price) / (10 ** meta.quoteDecimals) : market.capacity;

            /**
             * calculate the correct payout to complete on time assuming each bond
             * will be max size in the desired deposit interval for the remaining time
             *
             * i.e. market has 10 days remaining. deposit interval is 1 day. capacity
             * is 10,000 Acid. max payout would be 1,000 Acid (10,000 * 1 / 10).
             */

            // derive a new control variable from the target debt and current supply

            //DEV : replace with acid supply
            //uint64 newControlVariable = uint64((price * treasury.baseSupply()) / targetDebt);
            uint newControlVariable = (price * IERC20(acid).totalSupply()) / capacity;

            emit Tuned(_id, terms[_id].controlVariable, newControlVariable);

            if (newControlVariable >= terms[_id].controlVariable) {
                uint change = newControlVariable - terms[_id].controlVariable;
                adjustments[_id] = Adjustment(change, _time, meta.tuneInterval, true, true);
            } else {
                // if decrease, control variable change will be carried out over the tune interval
                // this is because price will be lowered
                uint change = terms[_id].controlVariable - newControlVariable;
                adjustments[_id] = Adjustment(change, _time, meta.tuneInterval, true, false);
            }
            metadata[_id].lastTune = _time;
        }
    }

    /* ======== SET MIN PRICE ======== */

    /**
     * @notice             set minimum price of the bond market
     * @param _id          ID of market
     * @param _minPrice    minimum price of the bond market, in 9 decimals (1e9 = 1 quote token per Acid)
     */
    function setMinPrice(uint256 _id, uint256 _minPrice) external onlyOwner {
        minMarketPrice[_id] = _minPrice;
    }

    function setTuneEnaled(uint256 _id, bool _enabled) external onlyOwner {
        metadata[_id].tuneEnabled = _enabled;
    }

    function setAdjustment(uint256 _id, uint change, uint timeToAdjusted, bool addition) external onlyOwner {
        adjustments[_id] = Adjustment(change, block.timestamp, timeToAdjusted, addition, true);
    }

    /* ======== CREATE ======== */

    /**
     * @notice             creates a new market type
     * @dev                current price should be in 9 decimals.
     * @param _quoteToken  token used to deposit
     * @param _market      [capacity (in Acid or quote), initial price / Acid (9 decimals), debt buffer (3 decimals)]
     * @param _booleans    [capacity in quote, fixed term, tune enabled]
     * @param _terms       [vesting length (if fixed term) or vested timestamp, debt decay term]
     * @param _intervals   [tune interval (seconds)]
     * @param minPrice     minimum price of the bond market
     * @return id_         ID of new bond market
     */
    function create(
        IERC20 _quoteToken,
        uint256[3] memory _market,
        bool[3] memory _booleans,
        uint256[2] memory _terms,
        uint32[1] memory _intervals,
        uint minPrice,
        uint64 maxPayout
    ) external onlyOwner returns (uint256 id_) {
        // the decimal count of the quote token
        uint256 decimals = IERC20Metadata(address(_quoteToken)).decimals();

        /*
         * initial target debt is equal to capacity (this is the amount of debt
         * that will decay over in the length of the program if price remains the same).
         * it is converted into base token terms if passed in in quote token terms.
         *
         * 1e18 = Acid decimals (9) + initial price decimals (9)
         */
        uint64 targetDebt = uint64(_booleans[0] ? ((_market[0] * 1e18) / _market[1]) / 10 ** decimals : _market[0]);

        /*
         * max payout is the amount of capacity that should be utilized in a deposit
         * interval. for example, if capacity is 1,000 Acid, there are 10 days to conclusion,
         * and the preferred deposit interval is 1 day, max payout would be 100 Acid.
         */

        /*
         * max debt serves as a circuit breaker for the market. let's say the quote
         * token is a stablecoin, and that stablecoin depegs. without max debt, the
         * market would continue to buy until it runs out of capacity. this is
         * configurable with a 3 decimal buffer (1000 = 1% above initial price).
         * note that its likely advisable to keep this buffer wide.
         * note that the buffer is above 100%. i.e. 10% buffer = initial debt * 1.1
         */
        uint256 maxDebt = targetDebt + ((targetDebt * _market[2]) / 1e5); // 1e5 = 100,000. 10,000 / 100,000 = 10%.

        /*
         * the control variable is set so that initial price equals the desired
         * initial price. the control variable is the ultimate determinant of price,
         * so we compute this last.
         *
         * price = control variable * debt ratio
         * debt ratio = total debt / supply
         * therefore, control variable = price / debt ratio
         */

        //DEV : replace with acid supply
        //uint256 controlVariable = (_market[1] * treasury.baseSupply()) / targetDebt;
        uint256 controlVariable = (_market[1] * IERC20(acid).totalSupply()) / targetDebt;

        // depositing into, or getting info for, the created market uses this ID
        id_ = markets.length;

        markets.push(
            Market({
                quoteToken: _quoteToken,
                capacityInQuote: _booleans[0],
                capacity: _market[0],
                totalDebt: targetDebt,
                maxPayout: maxPayout,
                purchased: 0,
                sold: 0
            })
        );

        terms.push(
            Terms({
                fixedTerm: _booleans[1],
                controlVariable: uint64(controlVariable),
                vesting: uint48(_terms[0]),
                maxDebt: uint64(maxDebt),
                debtDecayTerm: uint48(_terms[1])
            })
        );

        metadata.push(
            Metadata({
                lastTune: uint48(block.timestamp),
                lastDecay: uint48(block.timestamp),
                tuneInterval: _intervals[0],
                quoteDecimals: uint8(decimals),
                tuneEnabled: _booleans[2]
            })
        );

        marketsForQuote[address(_quoteToken)].push(id_);
        minMarketPrice[id_] = minPrice;

        emit CreateMarket(id_, address(acid), address(_quoteToken), _market[1]);
    }

    /**
     * @notice             disable existing market
     * @param _id          ID of market to close
     */
    function close(uint256 _id) external onlyOwner {
        markets[_id].capacity = 0;
        emit CloseMarket(_id);
    }

    /* ======== EXTERNAL VIEW ======== */

    /**
     * @notice             calculate current market price of quote token in base token, not considering min price
     * @dev                accounts for debt and control variable decay since last deposit (vs _marketPrice())
     * @param _id          ID of market
     * @return             price for market in Acid decimals
     *
     * price is derived from the equation
     *
     * p = cv * dr
     *
     * where
     * p = price
     * cv = control variable
     * dr = debt ratio
     *
     * dr = d / s
     *
     * where
     * d = debt
     * s = supply of token at market creation
     *
     * d -= ( d * (dt / l) )
     *
     * where
     * dt = change in time
     * l = length of program
     */
    function marketPrice(uint256 _id) public view returns (uint256 price) {
        price = (currentControlVariable(_id) * debtRatio(_id)) / (10 ** metadata[_id].quoteDecimals);
        if (price < minMarketPrice[_id]) {
            price = minMarketPrice[_id];
        }
    }

    /**
     * @notice             payout due for amount of quote tokens
     * @dev                accounts for debt and control variable decay so it is up to date
     * @param _amount      amount of quote tokens to spend
     * @param _id          ID of market
     * @return             amount of Acid to be paid in Acid decimals
     *
     * @dev 1e18 = Acid decimals (9) + market price decimals (9)
     */
    function payoutFor(uint256 _amount, uint256 _id) external view returns (uint256) {
        Metadata memory meta = metadata[_id];
        return (_amount * 1e18) / marketPrice(_id) / 10 ** meta.quoteDecimals;
    }

    /**
     * @notice             calculate current ratio of debt to supply
     * @dev                uses current debt, which accounts for debt decay since last deposit (vs _debtRatio())
     * @param _id          ID of market
     * @return             debt ratio for market in quote decimals
     */
    function debtRatio(uint256 _id) public view returns (uint256) {
        //DEV : replace with acid supply
        //return (markets[_id].totalDebt * (10**metadata[_id].quoteDecimals)) / treasury.baseSupply();
        return (markets[_id].totalDebt * (10 ** metadata[_id].quoteDecimals)) / IERC20(acid).totalSupply();
    }

    /**
     * @notice             calculate debt factoring in decay
     * @dev                accounts for debt decay since last deposit
     * @param _id          ID of market
     * @return             current debt for market in Acid decimals
     */
    function currentDebt(uint256 _id) public view returns (uint256) {
        return markets[_id].totalDebt - debtDecay(_id);
    }

    /**
     * @notice             amount of debt to decay from total debt for market ID
     * @param _id          ID of market
     * @return             amount of debt to decay
     */
    function debtDecay(uint256 _id) public view returns (uint64) {
        Metadata memory meta = metadata[_id];

        uint256 secondsSince = block.timestamp - meta.lastDecay;

        return uint64((markets[_id].totalDebt * secondsSince) / terms[_id].debtDecayTerm);
    }

    /**
     * @notice             up to date control variable
     * @dev                accounts for control variable adjustment
     * @param _id          ID of market
     * @return             control variable for market in Acid decimals
     */
    function currentControlVariable(uint256 _id) public view returns (uint256) {
        (uint decay, , , bool add) = _controlDecay(_id);
        return add ? (terms[_id].controlVariable + decay) : (terms[_id].controlVariable - decay);
    }

    /**
     * @notice             is a given market accepting deposits
     * @param _id          ID of market
     */
    function isLive(uint256 _id) public view returns (bool) {
        return (markets[_id].capacity != 0);
    }

    /**
     * @notice returns an array of all active market IDs
     */
    function liveMarkets() external view returns (uint256[] memory) {
        uint256 num;
        for (uint256 i; i < markets.length; i++) {
            if (isLive(i)) num++;
        }

        uint256[] memory ids = new uint256[](num);
        uint256 nonce;
        for (uint256 i; i < markets.length; i++) {
            if (isLive(i)) {
                ids[nonce] = i;
                nonce++;
            }
        }
        return ids;
    }

    /**
     * @notice             returns an array of all active market IDs for a given quote token
     * @param _token       quote token to check for
     */
    function liveMarketsFor(address _token) external view returns (uint256[] memory) {
        uint256[] memory mkts = marketsForQuote[_token];
        uint256 num;

        for (uint256 i; i < mkts.length; i++) {
            if (isLive(mkts[i])) num++;
        }

        uint256[] memory ids = new uint256[](num);
        uint256 nonce;

        for (uint256 i; i < mkts.length; i++) {
            if (isLive(mkts[i])) {
                ids[nonce] = mkts[i];
                nonce++;
            }
        }
        return ids;
    }

    /* ======== INTERNAL VIEW ======== */

    /**
     * @notice                  calculate current market price of quote token in base token
     * @dev                     see marketPrice() for explanation of price computation
     * @dev                     uses info from storage because data has been updated before call (vs marketPrice())
     * @param _id               market ID
     * @return                  price for market in Acid decimals
     */
    function _marketPrice(uint256 _id) internal view returns (uint256 price) {
        price = (terms[_id].controlVariable * _debtRatio(_id)) / (10 ** metadata[_id].quoteDecimals);

        //check if less than min price
        if (price < minMarketPrice[_id]) {
            price = minMarketPrice[_id];
        }
    }

    /**
     * @notice                  calculate debt factoring in decay
     * @dev                     uses info from storage because data has been updated before call (vs debtRatio())
     * @param _id               market ID
     * @return                  current debt for market in quote decimals
     */
    function _debtRatio(uint256 _id) internal view returns (uint256) {
        //DEV : replace with acid supply
        //return (markets[_id].totalDebt * (10**metadata[_id].quoteDecimals)) / treasury.baseSupply();
        return (markets[_id].totalDebt * (10 ** metadata[_id].quoteDecimals)) / IERC20(acid).totalSupply();
    }

    /**
     * @notice                  amount to decay or add control variable by
     * @param _id               ID of market
     * @return decay_           change in control variable
     * @return secondsSince_    seconds since last change in control variable
     * @return active_          whether or not change remains active
     */
    function _controlDecay(uint256 _id) internal view returns (uint decay_, uint secondsSince_, bool active_, bool add_) {
        Adjustment memory info = adjustments[_id];
        if (!info.active) return (0, 0, false, false);

        secondsSince_ = uint48(block.timestamp) - info.lastAdjustment;

        active_ = secondsSince_ < info.timeToAdjusted;
        decay_ = active_ ? (info.change * secondsSince_) / info.timeToAdjusted : info.change;
        add_ = info.addition;
    }

    /* ========== ADD ========== */

    /**
     * @notice             adds a new Note for a user, stores the front end & DAO rewards, and mints & stakes payout & rewards
     * @param _user        the user that owns the Note
     * @param _payout      the amount of Acid due to the user
     * @param _expiry      the timestamp when the Note is redeemable
     * @param _marketID    the ID of the market deposited into
     * @return index_      the index of the Note in the user's array
     */
    function addNote(address _user, uint256 _payout, uint48 _expiry, uint48 _marketID) internal returns (uint256 index_) {
        // the index of the note is the next in the user's array
        index_ = notes[_user].length;

        // the new note is pushed to the user's array
        notes[_user].push(Note({payout: _payout, created: uint48(block.timestamp), matured: _expiry, redeemed: 0, marketID: _marketID}));

        //mint payout, store in bond contract (remember check mint)
        uint bal = IERC20(acid).balanceOf(address(this));
        IMintableToken(acid).mint(address(this), _payout);
        require(IERC20(acid).balanceOf(address(this)) == bal + _payout, "Bond: mint failed");
    }

    /* ========== REDEEM ========== */

    /**
     * @notice             redeem notes for user
     * @param _user        the user to redeem for
     * @param _indexes     the note indexes to redeem
     * @return payout_     sum of payout sent
     */
    function redeem(address _user, uint256[] memory _indexes) public returns (uint256 payout_) {
        uint48 time = uint48(block.timestamp);

        for (uint256 i; i < _indexes.length; i++) {
            (uint256 pay, bool matured) = pendingFor(_user, _indexes[i]);

            if (matured) {
                notes[_user][_indexes[i]].redeemed = time; // mark as redeemed
                payout_ += pay;
            }
        }

        //send rewards to user
        IERC20(acid).transfer(_user, payout_);
    }

    /**
     * @notice             redeem all redeemable markets for user
     * @dev                if possible, query indexesFor() off-chain and input in redeem() to save gas
     * @param _user        user to redeem all notes for
     * @return             sum of payout sent
     */
    function redeemAll(address _user) external returns (uint256) {
        return redeem(_user, indexesFor(_user));
    }

    /* ========== TRANSFER ========== */

    /**
     * @notice             approve an address to transfer a note
     * @param _to          address to approve note transfer for
     * @param _index       index of note to approve transfer for
     */
    function pushNote(address _to, uint256 _index) external {
        require(notes[msg.sender][_index].created != 0, "Bond: note not found");
        noteTransfers[msg.sender][_index] = _to;
    }

    /**
     * @notice             transfer a note that has been approved by an address
     * @param _from        the address that approved the note transfer
     * @param _index       the index of the note to transfer (in the sender's array)
     */
    function pullNote(address _from, uint256 _index) external returns (uint256 newIndex_) {
        require(noteTransfers[_from][_index] == msg.sender, "Bond: transfer not found");
        require(notes[_from][_index].redeemed == 0, "Bond: note redeemed");

        newIndex_ = notes[msg.sender].length;
        notes[msg.sender].push(notes[_from][_index]);

        delete notes[_from][_index];
    }

    /* ========== VIEW ========== */

    // Note info

    /**
     * @notice             all pending notes for user
     * @param _user        the user to query notes for
     * @return             the pending notes for the user
     */
    function indexesFor(address _user) public view returns (uint256[] memory) {
        Note[] memory info = notes[_user];

        uint256 length;
        for (uint256 i; i < info.length; i++) {
            if (info[i].redeemed == 0 && info[i].payout != 0) length++;
        }

        uint256[] memory indexes = new uint256[](length);
        uint256 position;

        for (uint256 i; i < info.length; i++) {
            if (info[i].redeemed == 0 && info[i].payout != 0) {
                indexes[position] = i;
                position++;
            }
        }

        return indexes;
    }

    /**
     * @notice             calculate amount available for claim for a single note
     * @param _user        the user that the note belongs to
     * @param _index       the index of the note in the user's array
     * @return payout_     the payout due
     * @return matured_    if the payout can be redeemed
     */
    function pendingFor(address _user, uint256 _index) public view returns (uint256 payout_, bool matured_) {
        Note memory note = notes[_user][_index];

        payout_ = note.payout;
        matured_ = note.redeemed == 0 && note.matured <= block.timestamp && note.payout != 0;
    }
}

