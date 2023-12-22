// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./AccessControl.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Address.sol";

// import "hardhat/console.sol";

interface IRandomizer {
    function request(
        uint256 _callbackGasLimit,
        uint256 _confirmations
    ) external returns (uint256);

    function clientWithdrawTo(address _to, uint256 _amount) external;

    function estimateFee(
        uint256 _callbackGasLimit,
        uint256 _confirmations
    ) external view returns (uint256);

    function clientDeposit(address _client) external payable;

    function getFeeStats(
        uint256 _request
    ) external view returns (uint256[2] memory);
}

interface IGame {
    function receiveRandomNumbers(
        uint256 _id,
        uint256[] calldata expandedValues
    ) external;
}

contract LottoRNGV2 is AccessControl {
    using SafeERC20 for IERC20;
    using Address for address payable;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant GAME_ROLE = keccak256("GAME_ROLE");

    struct Request {
        address source;
        uint256 quantity;
        bytes32 vrfValue;
        uint256[] expandedValues;
        bool filled;
    }

    IRandomizer public randomizer;
    uint256 public confirmations = 1;
    uint256 public lastId;

    mapping(uint256 => Request) public requests;

    uint256 public lastValue;

    /* ========== INITIALIZER ========== */
    constructor(address _randomizerAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(OPERATOR_ROLE, _msgSender());
        randomizer = IRandomizer(_randomizerAddress);
    }

    /* ========== FUNCTIONS ========== */
    function requestRandomNumbers(
        uint256 n,
        uint256 gasLimit
    ) external payable onlyRole(GAME_ROLE) returns (uint256 id) {
        if (msg.value > 0) {
            randomizer.clientDeposit{value: msg.value}(address(this));
        }
        id = randomizer.request(gasLimit, confirmations);
        lastId = id;
        requests[id].source = _msgSender();
        requests[id].quantity = n;
        emit RandomNumberRequested(_msgSender(), id, gasLimit, n);
    }

    function depositFee() external payable onlyRole(GAME_ROLE) {
        randomizer.clientDeposit{value: msg.value}(address(this));
        emit DepositedToRandomizer(msg.value);
    }

    function randomizerCallback(uint256 _id, bytes32 _value) external {
        //Callback can only be called by randomizer
        require(msg.sender == address(randomizer), "Caller not Randomizer");
        require(requests[_id].filled == false, "RequestId already filled");
        lastValue = uint256(_value);
        uint256[] memory expandedValues = expand(
            uint256(_value),
            requests[_id].quantity
        );

        requests[_id].vrfValue = _value;
        requests[_id].expandedValues = expandedValues;
        requests[_id].filled = true;
        IGame(requests[_id].source).receiveRandomNumbers(_id, expandedValues);
        emit RandomizerCallback(
            requests[_id].source,
            _id,
            _value,
            expandedValues
        );
    }

    /* ========== ADMIN FUNCTIONS ========== */
    function setConfirmations(
        uint256 _confirmations
    ) external onlyRole(OPERATOR_ROLE) {
        confirmations = _confirmations;
        emit ConfirmationsChanged(_confirmations);
    }

    function withdrawFromRandomizer(
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) {
        randomizer.clientWithdrawTo(_msgSender(), amount);
        emit WithdrawnFromRandomizer(amount);
    }

    function addGame(address game) external onlyRole(OPERATOR_ROLE) {
        grantRole(GAME_ROLE, game);
        emit GameAdded(game);
    }

    function removeGame(address game) external onlyRole(OPERATOR_ROLE) {
        revokeRole(GAME_ROLE, game);
        emit GameRemoved(game);
    }

    function rescue(
        address erc20Address,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) {
        if (erc20Address == address(0)) {
            payable(_msgSender()).sendValue(amount);
        } else {
            IERC20(erc20Address).safeTransfer(_msgSender(), amount);
        }
    }

    function rescueAll(address erc20Address) external onlyRole(OPERATOR_ROLE) {
        if (erc20Address == address(0)) {
            payable(_msgSender()).sendValue(address(this).balance);
        } else {
            IERC20(erc20Address).safeTransfer(
                _msgSender(),
                IERC20(erc20Address).balanceOf(address(this))
            );
        }
    }

    function manualCallback(
        uint256 _id,
        bytes32 _value
    ) external onlyRole(OPERATOR_ROLE) {
        //Callback can only be called by operator
        require(requests[_id].filled == false, "RequestId already filled");
        lastValue = uint256(_value);
        uint256[] memory expandedValues = expand(
            uint256(_value),
            requests[_id].quantity
        );

        requests[_id].vrfValue = _value;
        requests[_id].expandedValues = expandedValues;
        requests[_id].filled = true;
        IGame(requests[_id].source).receiveRandomNumbers(_id, expandedValues);
        emit ManualCallback(requests[_id].source, _id, _value, expandedValues);
    }

    /* ========== GETTERS ========== */
    function getRandomNumbers(
        uint256 id
    ) external view returns (uint256[] memory expandedValues) {
        expandedValues = requests[id].expandedValues;
    }

    /* ========== UTILS ========== */
    function expand(
        uint256 randomValue,
        uint256 n
    ) internal pure returns (uint256[] memory expandedValues) {
        expandedValues = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            expandedValues[i] = uint256(keccak256(abi.encode(randomValue, i)));
        }
        return expandedValues;
    }

    function getFee(uint256 gasLimit) public view returns (uint256 fee) {
        fee = (randomizer.estimateFee(gasLimit, confirmations) * 125) / 100;
    }

    /* ========== EVENTS ========== */
    event RandomNumberRequested(
        address indexed game,
        uint256 id,
        uint256 gasLimit,
        uint256 quantity
    );
    event DepositedToRandomizer(uint256 amount);
    event RandomizerCallback(
        address indexed game,
        uint256 id,
        bytes32 value,
        uint256[] expandedValues
    );
    event ManualCallback(
        address indexed game,
        uint256 id,
        bytes32 value,
        uint256[] expandedValues
    );
    event ConfirmationsChanged(uint256 amount);
    event WithdrawnFromRandomizer(uint256 amount);
    event GameAdded(address gameAddress);
    event GameRemoved(address gameAddress);
}

