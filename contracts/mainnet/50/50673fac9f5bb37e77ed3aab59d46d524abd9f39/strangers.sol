// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ERC721PartnerSeaDrop } from "./ERC721PartnerSeaDrop.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

contract strangers is ERC721PartnerSeaDrop {
    /// Variable for Delegate Address
    address public delegateAddress;

    /// Point Multiplier
    uint256 public pointsMultiplier = 86400;

    /// BoardedToken Struct
    struct BoardedToken {
        /// Boarded state
        bool boarded;
        /// The time BoardedToken was boarded at
        uint48 timeBoarded;
        /// Last time of update for this BoardedToken
        uint48 timeLastUpdated;
    }

    /// Default boarding state
    bool public boardingState = false;

    /// Default boarding point transfer state
    bool public allowPointsTransfer = false;

    /// Mapping for BoardedToken Struct
    mapping(uint256 => BoardedToken) public checkTokenBoardStatus;

    /// Mapping for wallet address to Boarded Token IDs
    mapping(address => uint256[]) boardedTokenId;

    /// Mapping for Points to an Address
    mapping(address => uint256) boarderAcc;

    /// Errors
    error TokenBoardStatus(string message);
    error PointsTransferStatus(string message);
    error PointsAmount(string message);
    error BalanceAmount(string message);
    error BoardingState(string message);
    error NotOwnerOfToken(string message);
    error NotOwnerOrDelegate(string message);

    // =============================================================
    //                     Boarding Adjustments
    // =============================================================
    constructor(
        string memory name,
        string memory symbol,
        address administrator,
        address[] memory allowedSeaDrop
    ) ERC721PartnerSeaDrop(name, symbol, administrator, allowedSeaDrop) {}

    function getTimestamp() public view virtual returns (uint256) {
        return block.timestamp;
    }

    /// @notice Enables Boarding
    function enableBoarding() external onlyOwner {
        boardingState = true;
    }

    /// @notice Disables Boarding
    function disableBoarding() external onlyOwner {
        for (uint256 i = 1; i <= totalSupply(); ++i) {
            if (checkTokenBoardStatus[i].boarded) {
                boarderAcc[ownerOf(i)] += checkActiveBoardingPoints(i);
                checkTokenBoardStatus[i].boarded = false;
                checkTokenBoardStatus[i].timeBoarded = 0;
                checkTokenBoardStatus[i].timeLastUpdated = uint48(
                    getTimestamp()
                );
                boardedTokenId[ownerOf(i)].pop();
                emit Deboarded(msg.sender, i, getTimestamp());
            }
        }
        boardingState = false;
    }

    /// @dev Emitted when a token points are moved.
    event ActivePointsMoved(address owner, uint256 tokenId, uint256 value);

    /// @notice Moves active boarding points to owner's wallet
    /// @param _boardedToken Boarded token ID
    function withdrawActiveBoardingPoints(uint256 _boardedToken)
        external
        nonReentrant
    {
        boarderAcc[msg.sender] += checkActiveBoardingPoints(_boardedToken);
        if (!checkTokenBoardStatus[_boardedToken].boarded) {
            revert TokenBoardStatus("Token has not boarded!");
        }
        checkTokenBoardStatus[_boardedToken].timeLastUpdated = uint48(
            getTimestamp()
        );
        emit ActivePointsMoved(
            msg.sender,
            _boardedToken,
            checkActiveBoardingPoints(_boardedToken)
        );
    }

    /// @notice Sets Point Multiplier
    /// @param _time Enter multiplier in seconds
    function setPointMultiplier(uint256 _time) external onlyOwner {
        pointsMultiplier = _time;
    }

    /// @notice Set Transfer Points state
    /// @param _state true or false
    function setPointTransfersOn(bool _state) external onlyOwner {
        allowPointsTransfer = _state;
    }

    /// @notice Transfer Points to another address
    /// @param _to Receiving Address
    /// @param _amount Amount of Points
    function pointsTransfer(address _to, uint256 _amount) external {
        uint256 ownerBalance = checkWalletPointsBalance(msg.sender);
        if (allowPointsTransfer != true) {
            revert PointsTransferStatus(
                "Point transfers not active"
            );
        }
        if (_amount > ownerBalance) {
            revert PointsAmount(
                "You're tryin to send more points than you own!"
            );
        }
        boarderAcc[msg.sender] -= _amount;
        boarderAcc[_to] += _amount;
    }

    /// @dev Emitted when a token points are moved.
    event PointsAdded(address caller, address recipient, uint256 value);

    /// @dev Emitted when a token points are moved.
    event PointsSubtracted(address caller, address recipient, uint256 value);

    /// @notice Add points to an address
    /// @param _to Address
    /// @param _amount Amount of Points
    function pointsAdd(address[] memory _to, uint256 _amount)
        external
        delegateOrOwner
    {
        for (uint256 i = 0; i < _to.length; ++i) {
            boarderAcc[_to[i]] += _amount;
            emit PointsAdded(msg.sender, _to[i], _amount);
        }
    }

    /// @notice Remove points from an address
    /// @param _to Address
    /// @param _amount Amount of Points
    function pointsSubtract(address[] memory _to, uint256 _amount)
        external
        delegateOrOwner
    {
        for (uint256 i = 0; i < _to.length; ++i) {
            uint256 addressPointsBalance = checkWalletPointsBalance(_to[i]);
            if (addressPointsBalance < _amount) {
                revert BalanceAmount(
                    "This will result in a negative points balance."
                );
            }
            boarderAcc[_to[i]] -= _amount;
            emit PointsSubtracted(msg.sender, _to[i], _amount);
        }
    }

    // =============================================================
    //                       Boarding Functions
    // =============================================================

    /// @dev Emitted when a token is boarded.
    event Boarded(address owner, uint256 tokenId, uint256 value);

    /// @dev Emitted when a token is deboarded.
    event Deboarded(address owner, uint256 tokenId, uint256 value);

    /// @notice Boarding Function
    /// @param _boardableTokenId Token Id
    function boardToken(uint256 _boardableTokenId) public {
        if (boardingState != true) {
            revert BoardingState("Boarding is not active");
        }
        if (msg.sender != ownerOf(_boardableTokenId)) {
            revert NotOwnerOfToken(
                "Can't board a token you don't own!"
            );
        }
        BoardedToken storage _token = checkTokenBoardStatus[_boardableTokenId];
        if (_token.boarded) {
            revert TokenBoardStatus("Token already boarded!");
        }
        _token.timeBoarded = uint48(getTimestamp());
        _token.boarded = true;
        _token.timeLastUpdated = uint48(getTimestamp());
        emit Boarded(msg.sender, _boardableTokenId, getTimestamp());
        checkTokenBoardStatus[_boardableTokenId] = _token;
        boardedTokenId[msg.sender].push(_boardableTokenId);
    }

    /// @notice Multi-Boarding Function
    /// @param _boardableTokenIds Token Ids array
    function boardTokens(uint256[] memory _boardableTokenIds) external {
        for (uint256 i; i < _boardableTokenIds.length; i++) {
            boardToken(_boardableTokenIds[i]);
        }
    }

    /// @notice Deboarding function
    /// @param _boardableTokenId Token Id
    function deboardToken(uint256 _boardableTokenId) external {
        if (msg.sender != ownerOf(_boardableTokenId)) {
            revert NotOwnerOfToken(
                "You are not the owner of this token!"
            );
        }
        BoardedToken storage _token = checkTokenBoardStatus[_boardableTokenId];
        if (!_token.boarded) {
            revert TokenBoardStatus("Token has not boarded!");
        }
        uint256 tokenPoints = checkActiveBoardingPoints(_boardableTokenId);
        boarderAcc[msg.sender] += tokenPoints;
        _token.boarded = false;
        _token.timeBoarded = 0;
        _token.timeLastUpdated = uint48(getTimestamp());
        emit Deboarded(msg.sender, _boardableTokenId, getTimestamp());
        checkTokenBoardStatus[_boardableTokenId] = _token;
        uint256[] memory _boardedToken = boardedTokenId[msg.sender];
        for (uint256 i = 0; i < _boardedToken.length; ++i) {
            if (_boardedToken[i] == _boardableTokenId) {
                _boardedToken[i] = _boardedToken[_boardedToken.length - 1];
            }
        }
        boardedTokenId[msg.sender] = _boardedToken;
        boardedTokenId[msg.sender].pop();
    }

    // =============================================================
    //                        Contract Checks
    // =============================================================

    /// @notice Returns the active board points accumulated since the last update
    /// @param _boardedTokenId Boarded Token ID
    function checkActiveBoardingPoints(uint256 _boardedTokenId)
        public
        view
        returns (uint256 _points)
    {
        if (checkTokenBoardStatus[_boardedTokenId].boarded) {
            return ((getTimestamp() -
                checkTokenBoardStatus[_boardedTokenId].timeLastUpdated) /
                pointsMultiplier); // Time in minutes
        } else {
            return 0;
        }
    }

    /// @notice Returns account points balance
    /// @param _boarderAcc The address to query for
    function checkWalletPointsBalance(address _boarderAcc)
        public
        view
        returns (uint256 _points)
    {
        return boarderAcc[_boarderAcc];
    }

    /// @notice Returns token Ids of Boarded Tokens for a given address
    /// @param _boarderAcc The address to query for
    function checkWalletBoardedTokens(address _boarderAcc)
        external
        view
        returns (uint256[] memory)
    {
        return boardedTokenId[_boarderAcc];
    }

    // =============================================================
    //                   Delegate Control Modifier
    // =============================================================

    function setDelegate(address _delegate) external onlyOwner {
        delegateAddress = _delegate;
    }

    modifier delegateOrOwner() {
        if (msg.sender != owner() && msg.sender != delegateAddress) {
            revert NotOwnerOrDelegate(
                "You do not have permission to run this function!"
            );
        }
        _;
    }

    // =============================================================
    //                Deboard Tokens before Transfers
    // =============================================================

    /// @notice Override function to block token transfers when tokenId is boarded
    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
        BoardedToken storage _token = checkTokenBoardStatus[startTokenId];
        if (checkTokenBoardStatus[startTokenId].boarded) {
            uint256 tokenPoints = checkActiveBoardingPoints(startTokenId);
            boarderAcc[ownerOf(startTokenId)] += tokenPoints;
            _token.boarded = false;
            _token.timeBoarded = 0;
            _token.timeLastUpdated = uint48(getTimestamp());
            emit Deboarded(msg.sender, startTokenId, getTimestamp());
            checkTokenBoardStatus[startTokenId] = _token;
            uint256[] storage _boardedToken = boardedTokenId[msg.sender];
            for (uint256 i = 0; i < _boardedToken.length; ++i) {
                if (_boardedToken[i] == startTokenId) {
                    _boardedToken[i] = _boardedToken[_boardedToken.length - 1];
                }
            }
            boardedTokenId[msg.sender] = _boardedToken;
            boardedTokenId[msg.sender].pop();
        }
    }
}

