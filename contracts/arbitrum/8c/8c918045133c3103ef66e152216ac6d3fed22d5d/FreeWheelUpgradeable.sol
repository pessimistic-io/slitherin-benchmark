// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./GameFreeWheelUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

library Errors {
    error InvalidData();
}

library Structs {
    struct UserWager {
        uint256 waged;
        uint256 toClaim;
        uint256 claimed;
        uint256 lastPlayTimestamp;
    }
    struct WinningAmounts {
        uint256 value;
        uint256 amountToWin;
    }
}

contract FreeWheelUpgradeable is GameFreeWheelUpgradeable, ReentrancyGuardUpgradeable {
    uint256 public WAGER_PERCENT;
    uint256 public PERCENT_TO_UNLOCK;

    mapping(address => Structs.UserWager) public userWager;
    mapping(uint256 => uint256) public winningAmounts;
    uint256[] private winningAmountsArray;

    modifier onlyRNG() {
        if (msg.sender != address(rng)) {
            revert RNGUnauthorized(msg.sender);
        }
        _;
    }

    event GameSessionPlayed(
        address indexed user,
        uint256 amount,
        uint256[] randomValue
    );

    event UpdateWinningAmounts(Structs.WinningAmounts[] winningAmounts);

    event AddWagedAmount(address indexed user, uint256 amount);

    event Claim(
        address indexed user,
        uint256 amount
    );

    struct GameSession {
        address player;
    }

    mapping(bytes32 => GameSession) sessions;

    /** @dev Creates a contract.
     * @param _rootCaller Root caller of that contract.
     * @param _rng the callback contract
     * @param _winningAmounts Structs.WinningAmounts objects array which sets wheel.
     */
    function initialize(
        address _rng,
        address _rootCaller,
        Structs.WinningAmounts[] memory _winningAmounts
    ) public payable initializer {
        GameFreeWheelUpgradeable.initialize_(
            _rng,
            _rootCaller
        );
        __Ownable_init();
        uint256 added = 0;
        
        WAGER_PERCENT = 2_500;
        PERCENT_TO_UNLOCK = 100;

        for (uint256 i = 0; i < _winningAmounts.length; i++) {
            require(
                _winningAmounts[i].value < _winningAmounts.length &&
                    _winningAmounts[i].amountToWin != uint256(0)
            );

            if (winningAmounts[_winningAmounts[i].value] == uint256(0)) {
                added++;
            }

            winningAmounts[_winningAmounts[i].value] = _winningAmounts[i]
                .amountToWin;
            
            winningAmountsArray.push(_winningAmounts[i].value);
        }
        require(added == _winningAmounts.length);
    }

    /** @dev Plays a game called.
     */
    function play() public nonReentrant {
        Structs.UserWager memory _userWager = userWager[msg.sender];
        require(
            _userWager.lastPlayTimestamp + 86_400 < block.timestamp,
            "Timestamp not passed"
        );
        userWager[msg.sender].lastPlayTimestamp = block.timestamp;

        bytes32 requestId = rng.makeRequestUint256Array(1);

        sessions[requestId] = GameSession({player: msg.sender});
    }

    function fulfill(bytes32 requestId, uint256[] memory randomWords)
        external
        onlyRNG
    {
        GameSession memory session = sessions[requestId];

        require(
            sessions[requestId].player != address(0),
            "Request ID not known"
        );
        
        uint256 randomValue = randomWords[0] % winningAmountsArray.length;
        userWager[session.player].toClaim += winningAmounts[randomValue];
        emit GameSessionPlayed(
            session.player,
            winningAmounts[randomValue],
            randomWords
        );

        delete sessions[requestId];
    }

    /** @dev Adds waged amount. Called by proxyRouter.
     * @param _player Player wallet address.
     * @param _amount Player wallet address.
     */
    function addWagedAmount(address _player, uint256 _amount)
        public
        onlyOwnerOrRootCallerAccount
    {
        uint256 toAdd = _amount * WAGER_PERCENT * PERCENT_TO_UNLOCK / 100_000_000;
        userWager[_player].waged += toAdd;
        emit AddWagedAmount(_player, toAdd);
    }

    /** @dev Claims won amount
     */
    function claim()
        public nonReentrant
    {
        Structs.UserWager memory _userWager = userWager[msg.sender];
        uint256 _toClaim = _userWager.toClaim;

        // _maxAmountToClaim - _userWager.claimed - _toClaim > 0 
        // 500 - 0 - 30 > 0 true
        // 500 - 30 - 480 > 0 false NO.
        uint256 _amountToClaim = _userWager.waged - _userWager.claimed > _toClaim ? _toClaim : _userWager.waged - _userWager.claimed;
        require(_amountToClaim > 0);
        userWager[msg.sender].toClaim -= _amountToClaim;
        userWager[msg.sender].claimed += _amountToClaim;

        //send

        (bool success, ) = msg.sender.call{value: _amountToClaim}("");
        require(success, "Payout failed");
    
        emit Claim(msg.sender, _amountToClaim);
    }

    /** @dev Updates WinningAmounts array
     * @param _winningAmounts Structs.WinningAmounts objects array which sets wheel.
     */
    function updateWinningAmounts(
        Structs.WinningAmounts[] memory _winningAmounts
    ) public onlyOwner {
        uint256 added = 0;

        for (uint256 i = 0; i < winningAmountsArray.length; i++) {
            delete winningAmounts[winningAmountsArray[i]];
        }

        winningAmountsArray = new uint256[](0);

        for (uint256 i = 0; i < _winningAmounts.length; i++) {
            require(
                _winningAmounts[i].value < _winningAmounts.length &&
                    _winningAmounts[i].amountToWin != uint256(0)
            );

            if (winningAmounts[_winningAmounts[i].value] == uint256(0)) {
                added++;
            }

            winningAmounts[_winningAmounts[i].value] = _winningAmounts[i]
                .amountToWin;

            winningAmountsArray.push(_winningAmounts[i].value);
        }
        require(added == _winningAmounts.length);
        emit UpdateWinningAmounts(_winningAmounts);
    }
}

