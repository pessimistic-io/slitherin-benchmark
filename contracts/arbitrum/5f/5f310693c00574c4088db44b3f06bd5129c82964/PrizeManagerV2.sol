// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;
pragma experimental ABIEncoderV2;

import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./ERC20_IERC20.sol";
import "./Ownable.sol";
import "./IGamePolicy.sol";
import "./IPrizeManagerV2.sol";

contract PrizeManagerV2 is IPrizeManagerV2, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    struct PrizeInfo {
        address token;
        uint256 amount;
        address[] winners;
        address router;
        uint256 expire;
    }

    struct SidePrizeInfo {
        bool exist;
        address[] tokens;
        uint256[] amounts;
        uint256 expire;
    }

    // gameId => prize info
    mapping (uint256 => PrizeInfo) public prizeInfo;
    // user => gameId
    mapping (address => mapping(uint256 => uint256)) public isClaimable;
    // gameId => size prize
    mapping (uint256 => SidePrizeInfo) public sidePrizeInfo;

    IGamePolicy public gamePolicy;

    address public treasury;
    uint256 public prizeExpireTime = 7 * 1 days;

    /* ========== MODIFIERS ========== */

    modifier onlyGameRouter() {
        require(gamePolicy.isTournamentRouter(msg.sender), "PrizeManager: !TournamentRouter");
        _;
    }

    modifier onlyOperator() {
        require(gamePolicy.isOperator(msg.sender), "PrizeManager: !operator");
        _;
    }

    modifier onlyHeadsUpRouter() {
        require(gamePolicy.isHeadsUpRouter(msg.sender), "PrizeManager: !headsUp Router");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor (IGamePolicy _gamePolicy, address _treasury) {
        gamePolicy = _gamePolicy;
        treasury = _treasury;
    }

    /* ========== VIEWS ========== */

    /* ========== PUBLIC FUNCTIONS ========== */

    function claimPrize(uint256 _gameId, address _account) external nonReentrant {
        _claim(_gameId, _account);
    }

    function claimAll(uint256[] memory _gameIds, address _account) external nonReentrant {
        for (uint256 i = 0; i < _gameIds.length; i++) {
            _claim(_gameIds[i], _account);
        }
    }

    function batchClaim(uint256[] memory _gameIds, address[] memory _accounts) external nonReentrant {
        for (uint256 i = 0; i < _gameIds.length; i++) {
                _claim(_gameIds[i], _accounts[i]);
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _claim(uint256 _gameId, address _winner) internal {
        PrizeInfo memory _prizeInfo = prizeInfo[_gameId];
        if (_prizeInfo.expire < block.timestamp) {
            // transfer to treasury
            _winner = treasury;
        }
        if (isClaimable[_winner][_gameId] != 0) {
            isClaimable[_winner][_gameId] = 0;
            _transfer(_prizeInfo.token, _winner, _prizeInfo.amount);
            SidePrizeInfo memory _sidePrize = sidePrizeInfo[_gameId];
            if (_sidePrize.exist) {
                for (uint256 i = 0; i < _sidePrize.tokens.length; i++) {
                    // transfer token
                    _transfer(_sidePrize.tokens[i], _winner, _sidePrize.amounts[i]);
                }
            }
        }

    }

    function _transfer(address _token, address _receiver, uint256 _amount) internal {
        if (_token != address(0) && _receiver != address(0) && _amount > 0) {
            IERC20(_token).safeTransfer(_receiver, _amount);
        }
    }

    function _transferFrom(address _token, address _sender, address _receiver, uint256 _amount) internal {
        if (_token != address(0) && _receiver != address(0) && _amount > 0) {
            IERC20(_token).safeTransferFrom(_sender, _receiver, _amount);
        }
    }


    /* ========== RESTRICTED FUNCTIONS ========== */

    function createPrize(uint256 _gameId, address[] memory _winners, address _token, uint256 _amount) external onlyGameRouter {
        prizeInfo[_gameId] = PrizeInfo(
            _token,
            _amount,
            _winners,
            msg.sender,
            block.timestamp + prizeExpireTime
        );
        for (uint256 i = 0; i < _winners.length; i++) {
            isClaimable[_winners[i]][_gameId] = 1;
        }
    }

    function createSidePrize(uint256 _gameId, address[] memory _tokens, uint256[] memory _amounts) external onlyGameRouter {
        sidePrizeInfo[_gameId] = SidePrizeInfo(
            true,
            _tokens,
            _amounts,
            block.timestamp + prizeExpireTime
        );
    }

    function newWinners(uint256 _gameId, address[] memory _winners) external onlyGameRouter {
        prizeInfo[_gameId].winners = _winners;
        for (uint256 i = 0; i < _winners.length; i++) {
            isClaimable[_winners[i]][_gameId] = 1;
        }
    }

    function updatePrize(uint256 _gameId, uint256 _newAmount) external onlyGameRouter {
        PrizeInfo storage _prize = prizeInfo[_gameId];

        require(_prize.amount >= _newAmount, "PrizeManager: !newAmount");
        IERC20(_prize.token).safeTransfer(treasury, _prize.amount - _newAmount);
        _prize.amount = _newAmount;
    }

    function setExpireTime( uint256 _expireTime) external onlyOwner {
        prizeExpireTime = _expireTime;
    }

    // EVENTS
}
