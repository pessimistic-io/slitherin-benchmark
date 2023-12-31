// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "./SafeMath.sol";
import "./IERC20.sol";

import "./IAllowanceTarget.sol";
import "./ISpender.sol";
import "./BaseLibEIP712.sol";
import "./SignatureValidator.sol";

/**
 * @dev Spender contract
 */
contract Spender is ISpender, BaseLibEIP712, SignatureValidator {
    using SafeMath for uint256;

    // Constants do not have storage slot.
    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant ZERO_ADDRESS = address(0);
    uint256 private constant TIME_LOCK_DURATION = 1 days;
    /*
        keccak256(
            abi.encodePacked(
                "SpendWithPermit(",
                "address tokenAddr,",
                "address user,",
                "address recipient,",
                "uint256 amount,",
                "uint256 salt,",
                "uint64 expiry",
                ")"
            )
        );
    */
    uint256 private constant SPEND_WITH_PERMIT_TYPEHASH = 0xef4569e9739cba74d90490d1bd03bf9bb1ce2f4b9134ad0e79ba922a1f70c1a1;

    // Below are the variables which consume storage slots.
    bool public timelockActivated;
    uint64 public numPendingAuthorized;
    address public operator;

    address public allowanceTarget;
    address public pendingOperator;

    uint256 public contractDeployedTime;
    uint256 public timelockExpirationTime;

    mapping(address => bool) public consumeGasERC20Tokens;
    mapping(uint256 => address) public pendingAuthorized;

    mapping(address => bool) private authorized;
    mapping(bytes32 => bool) private spendingFulfilled;
    mapping(address => bool) private tokenBlacklist;

    // System events
    event TimeLockActivated(uint256 activatedTimeStamp);
    // Operator events
    event SetPendingOperator(address pendingOperator);
    event TransferOwnership(address newOperator);
    event SetAllowanceTarget(address allowanceTarget);
    event SetNewSpender(address newSpender);
    event SetConsumeGasERC20Token(address token);
    event TearDownAllowanceTarget(uint256 tearDownTimeStamp);
    event BlackListToken(address token, bool isBlacklisted);
    event AuthorizeSpender(address spender, bool isAuthorized);

    /************************************************************
     *          Access control and ownership management          *
     *************************************************************/
    modifier onlyOperator() {
        require(operator == msg.sender, "Spender: not the operator");
        _;
    }

    modifier onlyAuthorized() {
        require(authorized[msg.sender], "Spender: not authorized");
        _;
    }

    function setNewOperator(address _newOperator) external onlyOperator {
        require(_newOperator != address(0), "Spender: operator can not be zero address");
        pendingOperator = _newOperator;

        emit SetPendingOperator(_newOperator);
    }

    function acceptAsOperator() external {
        require(pendingOperator == msg.sender, "Spender: only nominated one can accept as new operator");
        operator = pendingOperator;
        pendingOperator = address(0);
        emit TransferOwnership(operator);
    }

    /************************************************************
     *                    Timelock management                    *
     *************************************************************/
    /// @dev Everyone can activate timelock after the contract has been deployed for more than 1 day.
    function activateTimelock() external {
        bool canActivate = block.timestamp.sub(contractDeployedTime) > 1 days;
        require(canActivate && !timelockActivated, "Spender: can not activate timelock yet or has been activated");
        timelockActivated = true;

        emit TimeLockActivated(block.timestamp);
    }

    /************************************************************
     *              Constructor and init functions               *
     *************************************************************/
    constructor(address _operator, address[] memory _consumeGasERC20Tokens) {
        require(_operator != address(0), "Spender: _operator should not be 0");

        // Set operator
        operator = _operator;
        timelockActivated = false;
        contractDeployedTime = block.timestamp;

        for (uint256 i = 0; i < _consumeGasERC20Tokens.length; i++) {
            consumeGasERC20Tokens[_consumeGasERC20Tokens[i]] = true;
        }
    }

    function setAllowanceTarget(address _allowanceTarget) external onlyOperator {
        require(allowanceTarget == address(0), "Spender: can not reset allowance target");

        // Set allowanceTarget
        allowanceTarget = _allowanceTarget;

        emit SetAllowanceTarget(_allowanceTarget);
    }

    /************************************************************
     *          AllowanceTarget interaction functions            *
     *************************************************************/
    function setNewSpender(address _newSpender) external onlyOperator {
        IAllowanceTarget(allowanceTarget).setSpenderWithTimelock(_newSpender);

        emit SetNewSpender(_newSpender);
    }

    function teardownAllowanceTarget() external onlyOperator {
        IAllowanceTarget(allowanceTarget).teardown();

        emit TearDownAllowanceTarget(block.timestamp);
    }

    /************************************************************
     *           Whitelist and blacklist functions               *
     *************************************************************/
    function isBlacklisted(address _tokenAddr) external view returns (bool) {
        return tokenBlacklist[_tokenAddr];
    }

    function blacklist(address[] calldata _tokenAddrs, bool[] calldata _isBlacklisted) external onlyOperator {
        require(_tokenAddrs.length == _isBlacklisted.length, "Spender: length mismatch");
        for (uint256 i = 0; i < _tokenAddrs.length; i++) {
            tokenBlacklist[_tokenAddrs[i]] = _isBlacklisted[i];

            emit BlackListToken(_tokenAddrs[i], _isBlacklisted[i]);
        }
    }

    function isAuthorized(address _caller) external view returns (bool) {
        return authorized[_caller];
    }

    function authorize(address[] calldata _pendingAuthorized) external onlyOperator {
        require(_pendingAuthorized.length > 0, "Spender: authorize list is empty");
        require(numPendingAuthorized == 0 && timelockExpirationTime == 0, "Spender: an authorize current in progress");

        if (timelockActivated) {
            numPendingAuthorized = uint64(_pendingAuthorized.length);
            for (uint256 i = 0; i < _pendingAuthorized.length; i++) {
                require(_pendingAuthorized[i] != address(0), "Spender: can not authorize zero address");
                pendingAuthorized[i] = _pendingAuthorized[i];
            }
            timelockExpirationTime = block.timestamp + TIME_LOCK_DURATION;
        } else {
            for (uint256 i = 0; i < _pendingAuthorized.length; i++) {
                require(_pendingAuthorized[i] != address(0), "Spender: can not authorize zero address");
                authorized[_pendingAuthorized[i]] = true;

                emit AuthorizeSpender(_pendingAuthorized[i], true);
            }
        }
    }

    function completeAuthorize() external {
        require(timelockExpirationTime != 0, "Spender: no pending authorize");
        require(block.timestamp >= timelockExpirationTime, "Spender: time lock not expired yet");

        for (uint256 i = 0; i < numPendingAuthorized; i++) {
            authorized[pendingAuthorized[i]] = true;
            emit AuthorizeSpender(pendingAuthorized[i], true);
            delete pendingAuthorized[i];
        }
        timelockExpirationTime = 0;
        numPendingAuthorized = 0;
    }

    function deauthorize(address[] calldata _deauthorized) external onlyOperator {
        for (uint256 i = 0; i < _deauthorized.length; i++) {
            authorized[_deauthorized[i]] = false;

            emit AuthorizeSpender(_deauthorized[i], false);
        }
    }

    function setConsumeGasERC20Tokens(address[] memory _consumeGasERC20Tokens) external onlyOperator {
        for (uint256 i = 0; i < _consumeGasERC20Tokens.length; i++) {
            consumeGasERC20Tokens[_consumeGasERC20Tokens[i]] = true;

            emit SetConsumeGasERC20Token(_consumeGasERC20Tokens[i]);
        }
    }

    /************************************************************
     *                   External functions                      *
     *************************************************************/
    /// @dev Spend tokens on user's behalf. Only an authority can call this.
    /// @param _user The user to spend token from.
    /// @param _tokenAddr The address of the token.
    /// @param _amount Amount to spend.
    function spendFromUser(
        address _user,
        address _tokenAddr,
        uint256 _amount
    ) external override onlyAuthorized {
        _transferTokenFromUserTo(_tokenAddr, _user, msg.sender, _amount);
    }

    /// @dev Spend tokens on user's behalf. Only an authority can call this.
    /// @param _user The user to spend token from.
    /// @param _tokenAddr The address of the token.
    /// @param _receiver The receiver of the token.
    /// @param _amount Amount to spend.
    function spendFromUserTo(
        address _user,
        address _tokenAddr,
        address _receiver,
        uint256 _amount
    ) external override onlyAuthorized {
        _transferTokenFromUserTo(_tokenAddr, _user, _receiver, _amount);
    }

    /// @dev Spend tokens on user's behalf with user's permit signature. Only an authority can call this.
    /// @param _tokenAddr The address of the token.
    /// @param _user The user to spend token from.
    /// @param _recipient The recipient of the token.
    /// @param _amount Amount to spend.
    /// @param _salt Salt for the permit.
    /// @param _expiry Expiry for the permit.
    /// @param _spendWithPermitSig Spend with permit signature.
    function spendFromUserToWithPermit(
        address _tokenAddr,
        address _user,
        address _recipient,
        uint256 _amount,
        uint256 _salt,
        uint64 _expiry,
        bytes calldata _spendWithPermitSig
    ) external override onlyAuthorized {
        require(_expiry > block.timestamp, "Spender: Permit is expired");

        // Validate spend with permit signature
        bytes32 spendWithPermitHash = getEIP712Hash(keccak256(abi.encode(SPEND_WITH_PERMIT_TYPEHASH, _tokenAddr, _user, _recipient, _amount, _salt, _expiry)));
        require(isValidSignature(_user, spendWithPermitHash, bytes(""), _spendWithPermitSig), "Spender: Invalid permit signature");

        // Validate spending is not replayed
        require(!spendingFulfilled[spendWithPermitHash], "Spender: Spending is already fulfilled");
        spendingFulfilled[spendWithPermitHash] = true;

        _transferTokenFromUserTo(_tokenAddr, _user, _recipient, _amount);
    }

    function _transferTokenFromUserTo(
        address _tokenAddr,
        address _user,
        address _recipient,
        uint256 _amount
    ) internal {
        require(!tokenBlacklist[_tokenAddr], "Spender: token is blacklisted");

        if (_tokenAddr == ETH_ADDRESS || _tokenAddr == ZERO_ADDRESS) {
            return;
        }
        // Fix gas stipend for non standard ERC20 transfer in case token contract's SafeMath violation is triggered
        // and all gas are consumed.
        uint256 gasStipend = consumeGasERC20Tokens[_tokenAddr] ? 80000 : gasleft();
        uint256 balanceBefore = IERC20(_tokenAddr).balanceOf(_recipient);

        (bool callSucceed, bytes memory returndata) = address(allowanceTarget).call{ gas: gasStipend }(
            abi.encodeWithSelector(
                IAllowanceTarget.executeCall.selector,
                _tokenAddr,
                abi.encodeWithSelector(IERC20.transferFrom.selector, _user, _recipient, _amount)
            )
        );
        require(callSucceed, "Spender: ERC20 transferFrom failed");

        bytes memory decodedReturnData = abi.decode(returndata, (bytes));
        if (decodedReturnData.length > 0) {
            // Return data is optional
            // Tokens like ZRX returns false on failed transfer
            require(abi.decode(decodedReturnData, (bool)), "Spender: ERC20 transferFrom failed");
        }

        // Check balance
        uint256 balanceAfter = IERC20(_tokenAddr).balanceOf(_recipient);
        require(balanceAfter.sub(balanceBefore) == _amount, "Spender: ERC20 transferFrom amount mismatch");
    }
}

