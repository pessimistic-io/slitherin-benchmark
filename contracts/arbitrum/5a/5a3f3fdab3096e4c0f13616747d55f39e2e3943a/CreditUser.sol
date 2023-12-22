// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";

import { ICreditUser } from "./ICreditUser.sol";

contract CreditUser is Initializable, ReentrancyGuardUpgradeable, ICreditUser {
    address public caller;
    uint256 public lendCreditIndex;

    mapping(address => uint256) internal creditCounts;
    mapping(uint256 => address) internal creditUsers;
    mapping(address => mapping(uint256 => UserLendCredit)) internal userLendCredits;
    mapping(address => mapping(uint256 => UserBorrowed)) internal userBorroweds;

    modifier onlyCaller() {
        require(caller == msg.sender, "CreditUser: Caller is not the caller");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(address _caller) external initializer {
        __ReentrancyGuard_init();

        caller = _caller;
    }

    function accrueSnapshot(address _recipient) external override onlyCaller returns (uint256) {
        lendCreditIndex++;
        creditCounts[_recipient]++;
        creditUsers[lendCreditIndex] = _recipient;

        return creditCounts[_recipient];
    }

    function createUserLendCredit(
        address _recipient,
        uint256 _borrowedIndex,
        address _depositor,
        address _token,
        uint256 _amountIn,
        address[] calldata _borrowedTokens,
        uint256[] calldata _ratios
    ) external override onlyCaller {
        UserLendCredit memory userLendCredit;

        userLendCredit.depositor = _depositor;
        userLendCredit.token = _token;
        userLendCredit.amountIn = _amountIn;
        userLendCredit.borrowedTokens = _borrowedTokens;
        userLendCredit.ratios = _ratios;

        userLendCredits[_recipient][_borrowedIndex] = userLendCredit;

        emit CreateUserLendCredit(_recipient, _borrowedIndex, _depositor, _token, _amountIn, _borrowedTokens, _ratios);
    }

    function createUserBorrowed(
        address _recipient,
        uint256 _borrowedIndex,
        address[] calldata _creditManagers,
        uint256[] calldata _borrowedAmountOuts,
        uint256 _collateralMintedAmount,
        uint256[] calldata _borrowedMintedAmount
    ) external override onlyCaller {
        UserBorrowed memory userBorrowed;

        userBorrowed.creditManagers = _creditManagers;
        userBorrowed.borrowedAmountOuts = _borrowedAmountOuts;
        userBorrowed.collateralMintedAmount = _collateralMintedAmount;
        userBorrowed.borrowedMintedAmount = _borrowedMintedAmount;
        userBorrowed.borrowedAt = block.timestamp;

        userBorroweds[_recipient][_borrowedIndex] = userBorrowed;

        emit CreateUserBorrowed(
            _recipient,
            _borrowedIndex,
            _creditManagers,
            _borrowedAmountOuts,
            _collateralMintedAmount,
            _borrowedMintedAmount,
            userBorrowed.borrowedAt
        );
    }

    function destroy(address _recipient, uint256 _borrowedIndex) external override onlyCaller {
        UserLendCredit storage userLendCredit = userLendCredits[_recipient][_borrowedIndex];

        userLendCredit.terminated = true;

        emit Destroy(_recipient, _borrowedIndex);
    }

    function isTerminated(address _recipient, uint256 _borrowedIndex) external view override returns (bool) {
        UserLendCredit storage userLendCredit = userLendCredits[_recipient][_borrowedIndex];
        return userLendCredit.terminated;
    }

    function isTimeout(
        address _recipient,
        uint256 _borrowedIndex,
        uint256 _duration
    ) external view override returns (bool) {
        UserBorrowed storage userBorrowed = userBorroweds[_recipient][_borrowedIndex];
        return block.timestamp - userBorrowed.borrowedAt > _duration;
    }

    function getUserLendCredit(address _recipient, uint256 _borrowedIndex)
        external
        view
        override
        returns (
            address depositor,
            address token,
            uint256 amountIn,
            address[] memory borrowedTokens,
            uint256[] memory ratios
        )
    {
        UserLendCredit storage userLendCredit = userLendCredits[_recipient][_borrowedIndex];

        depositor = userLendCredit.depositor;
        token = userLendCredit.token;
        amountIn = userLendCredit.amountIn;
        borrowedTokens = userLendCredit.borrowedTokens;
        ratios = userLendCredit.ratios;
    }

    function getUserBorrowed(address _recipient, uint256 _borrowedIndex)
        external
        view
        override
        returns (
            address[] memory creditManagers,
            uint256[] memory borrowedAmountOuts,
            uint256 collateralMintedAmount,
            uint256[] memory borrowedMintedAmount,
            uint256 mintedAmount
        )
    {
        UserBorrowed storage userBorrowed = userBorroweds[_recipient][_borrowedIndex];

        for (uint256 i = 0; i < userBorrowed.borrowedMintedAmount.length; i++) {
            mintedAmount = mintedAmount + userBorrowed.borrowedMintedAmount[i];
        }

        mintedAmount = mintedAmount + userBorrowed.collateralMintedAmount;

        creditManagers = userBorrowed.creditManagers;
        borrowedAmountOuts = userBorrowed.borrowedAmountOuts;
        collateralMintedAmount = userBorrowed.collateralMintedAmount;
        borrowedMintedAmount = userBorrowed.borrowedMintedAmount;
    }

    function getUserCounts(address _recipient) external view override returns (uint256) {
        return creditCounts[_recipient];
    }

    function getLendCreditUsers(uint256 _borrowedIndex) external view override returns (address) {
        return creditUsers[_borrowedIndex];
    }
}

