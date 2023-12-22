// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";

import "./CoreAdmin.sol";

import "./IGToken.sol";
import "./IValidator.sol";
import "./IPriceCalculator.sol";

contract Core is CoreAdmin {
    using SafeMath for uint256;

    /* ========== CONSTANT VARIABLES ========== */

    address internal constant ETH = 0x0000000000000000000000000000000000000000;

    /* ========== STATE VARIABLES ========== */

    mapping(address => address[]) public marketListOfUsers; // (account => gTokenAddress[])
    mapping(address => mapping(address => bool)) public usersOfMarket; // (gTokenAddress => (account => joined))

    /* ========== INITIALIZER ========== */

    function initialize(address _priceCalculator) external initializer {
        __Core_init();
        priceCalculator = IPriceCalculator(_priceCalculator);
    }

    /* ========== MODIFIERS ========== */

    /// @dev sender 가 해당 gToken 의 Market Enter 되어있는 상태인지 검사
    /// @param gToken 검사할 Market 의 gToken address
    modifier onlyMemberOfMarket(address gToken) {
        require(usersOfMarket[gToken][msg.sender], "Core: must enter market");
        _;
    }

    /// @dev caller 가 market 인지 검사
    modifier onlyMarket() {
        bool fromMarket = false;
        for (uint256 i = 0; i < markets.length; i++) {
            if (msg.sender == markets[i]) {
                fromMarket = true;
                break;
            }
        }
        require(fromMarket == true, "Core: caller should be market");
        _;
    }

    /* ========== VIEWS ========== */

    /// @notice market addresses 조회
    /// @return markets address[]
    function allMarkets() external view override returns (address[] memory) {
        return markets;
    }

    /// @notice gToken 의 marketInfo 조회
    /// @param gToken gToken address
    /// @return Market info
    function marketInfoOf(address gToken) external view override returns (Constant.MarketInfo memory) {
        return marketInfos[gToken];
    }

    /// @notice account 의 market addresses
    /// @param account account address
    /// @return Market addresses of account
    function marketListOf(address account) external view override returns (address[] memory) {
        return marketListOfUsers[account];
    }

    /// @notice account market enter 상태인지 여부 조회
    /// @param account account address
    /// @param gToken gToken address
    /// @return Market enter 여부에 대한 boolean value
    function checkMembership(address account, address gToken) external view override returns (bool) {
        return usersOfMarket[gToken][account];
    }

    /// @notice !TBD
    function accountLiquidityOf(
        address account
    ) external view override returns (uint256 collateralInUSD, uint256 supplyInUSD, uint256 borrowInUSD) {
        return IValidator(validator).getAccountLiquidity(account);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /// @notice 여러 token 에 대하여 Enter Market 수행
    /// @dev 해당 Token 을 대출하거나, 담보로 enable 하기 위해서는 Enter Market 이 필요함
    /// @param gTokens gToken addresses
    function enterMarkets(address[] memory gTokens) public override {
        for (uint256 i = 0; i < gTokens.length; i++) {
            _enterMarket(payable(gTokens[i]), msg.sender);
        }
    }

    /// @notice 하나의 token 에 대하여 Market Exit 수행
    /// @dev Market 에서 제거할 시에 해당 토큰이 담보물에서 제거되어 청산되지 않음
    /// @param gToken Token address
    function exitMarket(address gToken) external override onlyListedMarket(gToken) onlyMemberOfMarket(gToken) {
        Constant.AccountSnapshot memory snapshot = IGToken(gToken).accruedAccountSnapshot(msg.sender);
        require(snapshot.borrowBalance == 0, "Core: borrow balance must be zero");
        require(IValidator(validator).redeemAllowed(gToken, msg.sender, snapshot.gTokenBalance), "Core: cannot redeem");

        _removeUserMarket(gToken, msg.sender);
        emit MarketExited(gToken, msg.sender);
    }

    /// @notice 담보 제공 트랜잭션
    /// @param gToken 담보 gToken address
    /// @param uAmount 담보 gToken amount
    /// @return gAmount
    function supply(
        address gToken,
        uint256 uAmount
    ) external payable override onlyListedMarket(gToken) nonReentrant whenNotPaused returns (uint256) {
        uAmount = IGToken(gToken).underlying() == address(ETH) ? msg.value : uAmount;
        uint256 supplyCap = marketInfos[gToken].supplyCap;
        require(
            supplyCap == 0 ||
                IGToken(gToken).totalSupply().mul(IGToken(gToken).exchangeRate()).div(1e18).add(uAmount) <= supplyCap,
            "Core: supply cap reached"
        );

        uint256 gAmount = IGToken(gToken).supply{value: msg.value}(msg.sender, uAmount);
        grvDistributor.notifySupplyUpdated(gToken, msg.sender);

        emit MarketSupply(msg.sender, gToken, uAmount);
        return gAmount;
    }

    /// @notice 담보로 제공한 토큰을 전부 Redeem All
    /// @param gToken 담보 gToken address
    /// @param gAmount 담보 gToken redeem amount
    /// @return uAmountRedeem
    function redeemToken(
        address gToken,
        uint256 gAmount
    ) external override onlyListedMarket(gToken) nonReentrant whenNotPaused returns (uint256) {
        uint256 uAmountRedeem = IGToken(gToken).redeemToken(msg.sender, gAmount);
        grvDistributor.notifySupplyUpdated(gToken, msg.sender);

        emit MarketRedeem(msg.sender, gToken, uAmountRedeem);
        return uAmountRedeem;
    }

    /// @notice 담보로 제공한 토큰 중 일부를 Redeem
    /// @param gToken 담보 gToken address
    /// @param uAmount 담보 gToken redeem amount
    /// @return uAmountRedeem
    function redeemUnderlying(
        address gToken,
        uint256 uAmount
    ) external override onlyListedMarket(gToken) nonReentrant whenNotPaused returns (uint256) {
        uint256 uAmountRedeem = IGToken(gToken).redeemUnderlying(msg.sender, uAmount);
        grvDistributor.notifySupplyUpdated(gToken, msg.sender);

        emit MarketRedeem(msg.sender, gToken, uAmountRedeem);
        return uAmountRedeem;
    }

    /// @notice 원하는 자산을 Borrow 하는 트랜잭션
    /// @param gToken 빌리는 gToken address
    /// @param amount 빌리는 underlying token amount
    function borrow(
        address gToken,
        uint256 amount
    ) external override onlyListedMarket(gToken) nonReentrant whenNotPaused {
        _enterMarket(gToken, msg.sender);
        require(IValidator(validator).borrowAllowed(gToken, msg.sender, amount), "Core: cannot borrow");

        IGToken(payable(gToken)).borrow(msg.sender, amount);
        grvDistributor.notifyBorrowUpdated(gToken, msg.sender);
    }

    function nftBorrow(
        address gToken,
        address user,
        uint256 amount
    ) external override onlyListedMarket(gToken) onlyNftCore nonReentrant whenNotPaused {
        require(IGToken(gToken).underlying() == address(ETH), "Core: invalid underlying asset");
        _enterMarket(gToken, msg.sender);
        IGToken(payable(gToken)).borrow(msg.sender, amount);
        grvDistributor.notifyBorrowUpdated(gToken, user);
    }

    /// @notice 대출한 자산을 상환하는 트랜잭션
    /// @dev UI 에서의 Repay All 도 본 트랜잭션을 사용함
    ///      amount 를 넉넉하게 주면 repay 후 초과분은 환불함
    /// @param gToken 상환하려는 gToken address
    /// @param amount 상환하려는 gToken amount
    function repayBorrow(
        address gToken,
        uint256 amount
    ) external payable override onlyListedMarket(gToken) nonReentrant whenNotPaused {
        IGToken(payable(gToken)).repayBorrow{value: msg.value}(msg.sender, amount);
        grvDistributor.notifyBorrowUpdated(gToken, msg.sender);
    }

    function nftRepayBorrow(
        address gToken,
        address user,
        uint256 amount
    ) external payable override onlyListedMarket(gToken) onlyNftCore nonReentrant whenNotPaused {
        require(IGToken(gToken).underlying() == address(ETH), "Core: invalid underlying asset");
        IGToken(payable(gToken)).repayBorrow{value: msg.value}(msg.sender, amount);
        grvDistributor.notifyBorrowUpdated(gToken, user);
    }

    /// @notice 본인이 아닌 특정한 주소의 대출을 청산시키는 트랜잭션
    /// @dev UI 에서 본 트랜잭션 호출을 확인하지 못했음
    /// @param gToken 상환하려는 gToken address
    /// @param amount 상환하려는 gToken amount
    function repayBorrowBehalf(
        address gToken,
        address borrower,
        uint256 amount
    ) external payable override onlyListedMarket(gToken) nonReentrant whenNotPaused {
        IGToken(payable(gToken)).repayBorrowBehalf{value: msg.value}(msg.sender, borrower, amount);
        grvDistributor.notifyBorrowUpdated(gToken, borrower);
    }

    /// @notice 본인이 아닌 특정한 주소의 대출을 청산시키는 트랜잭션
    /// @dev UI 에서 본 트랜잭션 호출을 확인하지 못했음
    function liquidateBorrow(
        address gTokenBorrowed,
        address gTokenCollateral,
        address borrower,
        uint256 amount
    ) external payable override nonReentrant whenNotPaused {
        amount = IGToken(gTokenBorrowed).underlying() == address(ETH) ? msg.value : amount;
        require(marketInfos[gTokenBorrowed].isListed && marketInfos[gTokenCollateral].isListed, "Core: invalid market");
        require(usersOfMarket[gTokenCollateral][borrower], "Core: not a collateral");
        require(marketInfos[gTokenCollateral].collateralFactor > 0, "Core: not a collateral");
        require(
            IValidator(validator).liquidateAllowed(gTokenBorrowed, borrower, amount, closeFactor),
            "Core: cannot liquidate borrow"
        );

        (, uint256 rebateGAmount, uint256 liquidatorGAmount) = IGToken(gTokenBorrowed).liquidateBorrow{
            value: msg.value
        }(gTokenCollateral, msg.sender, borrower, amount);

        IGToken(gTokenCollateral).seize(msg.sender, borrower, liquidatorGAmount);
        grvDistributor.notifyTransferred(gTokenCollateral, borrower, msg.sender);

        if (rebateGAmount > 0) {
            IGToken(gTokenCollateral).seize(rebateDistributor, borrower, rebateGAmount);
            grvDistributor.notifyTransferred(gTokenCollateral, borrower, rebateDistributor);
        }

        grvDistributor.notifyBorrowUpdated(gTokenBorrowed, borrower);

        IRebateDistributor(rebateDistributor).addRebateAmount(
            gTokenCollateral,
            rebateGAmount.mul(IGToken(gTokenCollateral).accruedExchangeRate()).div(1e18)
        );
    }

    /// @notice 모든 마켓의 Reward GRV 클레임 트랜잭션
    function claimGRV() external override nonReentrant {
        grvDistributor.claimGRV(markets, msg.sender);
    }

    /// @notice 하나의 market 의 Reward GRV 클레임 트랜잭션
    /// @param market 클레임 하는 market 의 address
    function claimGRV(address market) external override nonReentrant {
        address[] memory _markets = new address[](1);
        _markets[0] = market;
        grvDistributor.claimGRV(_markets, msg.sender);
    }

    /// @notice 모든 마켓의 Reward GRV 재락업 트랜잭션
    function compoundGRV() external override {
        grvDistributor.compound(markets, msg.sender);
    }

    /// @notice 모든 마켓의 Reward GRV 재락업 트랜잭션
    function firstDepositGRV(uint256 expiry) external override {
        grvDistributor.firstDeposit(markets, msg.sender, expiry);
    }

    /// @notice Called when gToken has transfered
    /// @dev gToken 에서 grvDistributor 의 메서드를 호출하기 위해 중간 역할을 함
    ///      gToken -> Core -> gToken, grvDistributor
    function transferTokens(
        address spender,
        address src,
        address dst,
        uint256 amount
    ) external override nonReentrant onlyMarket {
        IGToken(msg.sender).transferTokensInternal(spender, src, dst, amount);
        grvDistributor.notifyTransferred(msg.sender, src, dst);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /// @notice Enter Market
    /// @dev 해당 Token 을 대출하거나, 담보로 enable 하기 위해서는 Enter Market 이 필요함
    /// @param gToken Token address
    /// @param _account Market 에 Enter 할 account address
    function _enterMarket(address gToken, address _account) internal onlyListedMarket(gToken) {
        if (!usersOfMarket[gToken][_account]) {
            usersOfMarket[gToken][_account] = true;
            marketListOfUsers[_account].push(gToken);
            emit MarketEntered(gToken, _account);
        }
    }

    /// @notice remove user from market
    /// @dev Market 에서 제거할 시에 해당 토큰이 담보물에서 제거되어 청산되지 않음
    /// @param gTokenToExit Token address
    /// @param _account Market 에 제거할 account address
    function _removeUserMarket(address gTokenToExit, address _account) private {
        require(marketListOfUsers[_account].length > 0, "Core: cannot pop user market");
        delete usersOfMarket[gTokenToExit][_account];

        uint256 length = marketListOfUsers[_account].length;
        for (uint256 i = 0; i < length; i++) {
            if (marketListOfUsers[_account][i] == gTokenToExit) {
                marketListOfUsers[_account][i] = marketListOfUsers[_account][length - 1];
                marketListOfUsers[_account].pop();
                break;
            }
        }
    }
}

