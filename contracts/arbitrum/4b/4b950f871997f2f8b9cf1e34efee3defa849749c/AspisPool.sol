pragma solidity 0.8.10;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Address.sol";
import "./ReentrancyGuard.sol";
import "./ACL.sol";
import "./ITokenValueCalculator.sol";
import "./IAspisPool.sol";
import "./IAspisGovernanceERC20.sol";
import "./IAspisConfiguration.sol";
import "./AspisProposal.sol";
import "./AspisLibrary.sol";
import "./IAspisRegistry.sol";
import "./IAspisDecoder.sol";
import "./Permit2Lib.sol";
import "./ECDSAExternal.sol";

contract AspisPool is
    IAspisPool,
    Initializable,
    UUPSUpgradeable,
    ACL,
    AspisProposal,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using Address for address;

    uint256 internal constant SUPPORTED_USD_DECIMALS = 4;

    uint256 internal constant SUPPORTED_TIME_UNIT = 1 days;

    // Roles
    bytes32 public constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");
    bytes32 public constant DAO_CONFIG_ROLE = keccak256("DAO_CONFIG_ROLE");
    bytes32 public constant EXEC_ROLE = keccak256("EXEC_ROLE");

    uint256 internal constant SLIPPAGE_TOLERANCE_PERCENTAGE = 500;
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    bytes4 private constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    bool public emergencyStopActivated;
    
    ITokenValueCalculator private calculator;
    IAspisGovernanceERC20 private token;
    IAspisRegistry private registry;
    address private guardian;
    IAspisConfiguration public configuration;

    //to know if there has been at least one deposit after DAO creation
    bool internal hasUsedDeposit;

    struct Deposit {
        uint256 price;
        uint256 amount;
    }

    address internal manager;
    uint256 public managerBalance;

    uint256 private lastFundManagementFeeTimestamp;

    mapping(address => uint256) private lockedUntil;
    mapping(address => Deposit[]) private depositsOfUser;
    mapping(address => uint256) private worthOfUserAsset; 

    // Error msg's
    /// @notice Thrown if action execution has failed
    error ActionFailed();

    /// @notice Thrown if the deposit or withdraw amount is zero
    error ZeroAmount();

    /// @notice Thrown if the expected and actually deposited ETH amount mismatch
    /// @param expected ETH amount
    /// @param actual ETH amount
    error ETHDepositAmountMismatch(uint256 expected, uint256 actual);

    /// @notice Thrown if an ETH withdraw fails
    error ETHWithdrawFailed();
    error EmergencyMode();
    error NotManager();
    error NotGuardian();
    error UnsupportedProtocol();
    error UnsupportedToken();
    error InvalidSignature(uint8 code);
    error TradeExceededSlippageTolerance();
    error FundraisingOverOrNotStarted();
    error FundraisingInProgress();
    error UserNotWhitelisted();
    error DepositLimitError();
    error AssetsLocked();

    modifier notEmergencyMode() {
        if (emergencyStopActivated) revert EmergencyMode();
        _;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    modifier trustedProtocol(address protocol) {
        if (!configuration.supportsProtocol(protocol)) revert UnsupportedProtocol();
        _;
    }

    function initialize(
        address[7] calldata _configurationAddresses
    ) external initializer {
        calculator = ITokenValueCalculator(_configurationAddresses[2]);
        token = IAspisGovernanceERC20(_configurationAddresses[1]);
        configuration = IAspisConfiguration(_configurationAddresses[3]);
        registry = IAspisRegistry(_configurationAddresses[4]);
        manager = _configurationAddresses[5];
        guardian = _configurationAddresses[6];
        __ACL_init(_configurationAddresses[0]);

    }

    /// @dev Used to check the permissions within the upgradability pattern implementation of OZ
    function _authorizeUpgrade(address) internal virtual override auth(address(this), UPGRADE_ROLE) {}

    /// @notice Checks if the current callee has the permissions for.
    /// @dev Wrapper for the willPerform method of ACL to later on be able to use it in the modifier of the sub components of this DAO.
    /// @param _where Which contract does get called
    /// @param _who Who is calling this method
    /// @param _role Which role is required to call this
    /// @param _data Additional data used in the ACLOracle
    function hasPermission(
        address _where,
        address _who,
        bytes32 _role,
        bytes memory _data
    ) external override returns (bool) {
        return willPerform(_where, _who, _role, _data);
    }
    

    function updateManager(address _manager) external auth(address(this), DAO_CONFIG_ROLE) {
        manager = _manager;
    }


    function deposit(address _token, uint256 _amount) external payable override nonReentrant notEmergencyMode {
        if (!configuration.supportsDepositToken(_token)) {
            revert UnsupportedToken();
        }
        
        if (_amount == 0) revert ZeroAmount();

        if (!configuration.isPublicFund() && !configuration.userWhitelisted(msg.sender)) {
            revert UserNotWhitelisted();
        }

        if (block.timestamp < configuration.startTime() || configuration.finishTime() < block.timestamp) {
            revert FundraisingOverOrNotStarted();
        }

        uint256 _depositValue = calculator.convert(_token, _amount);
        validateDepositLimit(_depositValue, msg.sender);

        lockedUntil[msg.sender] = block.timestamp + (1 hours * configuration.lockLimit());

        uint256 _fundManagementFee = hasUsedDeposit ? fundManagementFee() : 0;
        managerBalance += _fundManagementFee;

        (uint256 _price, ) = getCurrentTokenPrice(_token == ETH && msg.value != 0 ? _amount : 0);
        
        lastFundManagementFeeTimestamp = block.timestamp;

        if (!hasUsedDeposit) {
            hasUsedDeposit = true;
        }

        if (_token == address(ETH)) {
            if (msg.value != _amount) revert ETHDepositAmountMismatch({expected: _amount, actual: msg.value});
        } else {
            if (msg.value != 0) revert ETHDepositAmountMismatch({expected: 0, actual: msg.value});

            IERC20 depositToken = IERC20(_token);
            uint256 balBefore = depositToken.balanceOf(address(this));
            depositToken.safeTransferFrom(msg.sender, address(this), _amount);
            uint256 balAfter = depositToken.balanceOf(address(this));

            require(balAfter - balBefore >= _amount, "Error");
        }

        uint256 _mintTokens = (_depositValue * (10**token.decimals())) / (_price);
        uint256 _entranceFee = (_mintTokens * configuration.entranceFee()) / (10000);

        worthOfUserAsset[msg.sender] += _depositValue;

        token.mint(msg.sender, _mintTokens - _entranceFee);
        managerBalance += _entranceFee;

        depositsOfUser[msg.sender].push(Deposit(_price, _mintTokens - _entranceFee));

        emit Deposited(msg.sender, _token, _amount, _mintTokens, _entranceFee, _fundManagementFee);

    }

    function withdraw(
        address _to
    ) external override nonReentrant {

        uint256 _amount = token.balanceOf(msg.sender);

        if (_amount == 0) revert ZeroAmount();

        if (lockedUntil[msg.sender] >= block.timestamp) revert AssetsLocked();

        uint256 _fundManagementFee = fundManagementFee();

        managerBalance += _fundManagementFee;

        (uint256 _currentLPTokenPrice, uint256 _poolValue) = getCurrentTokenPrice(0);
        
        lastFundManagementFeeTimestamp = block.timestamp;

        uint256 _rageQuitFee = isRageQuitFeeRequired() ? (_amount * configuration.rageQuitFee()) / 10000 : 0;

        Deposit[] memory _deposits = depositsOfUser[msg.sender];

        uint256 _totalSupply = getTokenSupply();

        uint256 _weightedAveragePrice = 0;

        uint256 i = _deposits.length;
        for (i; i > 0; ) {
            unchecked { --i; }
            _weightedAveragePrice += (_deposits[i].amount * _deposits[i].price) / _amount;
            depositsOfUser[msg.sender].pop();
        }

        uint256 _performanceFee = AspisLibrary.calculatePerformanceFee(_currentLPTokenPrice, _weightedAveragePrice, _amount, _totalSupply, _poolValue, configuration.performanceFee());

        worthOfUserAsset[msg.sender] = 0;

        token.burn(msg.sender, _amount); 
        //burning with rage quit fee
        managerBalance += _performanceFee; 

        transferAsset(registry.getAspisSupportedTradingTokens(), _to, _amount - _rageQuitFee, _totalSupply + _performanceFee); // 8, 10

        emit Withdrawn(address(0), _to, _amount, _rageQuitFee, _fundManagementFee, _performanceFee);
    }

    function withdrawCommission() external nonReentrant onlyManager {
        uint256 _amount = managerBalance;
        
        uint256 _LPTokenSupply = getTokenSupply();
        
        managerBalance = 0;

        transferAsset(registry.getAspisSupportedTradingTokens(), msg.sender, _amount, _LPTokenSupply);

    }

    /// @notice If called, the list of provided actions will be executed.
    /// @dev It run a loop through the array of acctions and execute one by one.
    /// @dev If one acction fails, all will be reverted.
    /// @param _actions The aray of actions
    function execute(uint256 callId, Action[] memory _actions)
        external
        override
        auth(address(this), EXEC_ROLE)
        notEmergencyMode
        returns (bytes[] memory)
    {
        bytes[] memory execResults = new bytes[](_actions.length);

        for (uint256 i = 0; i < _actions.length; i++) {
            (bool success, bytes memory response) = _actions[i].to.call{value: _actions[i].value}(_actions[i].data);

            if (!success) revert ActionFailed();

            execResults[i] = response;
        }

        emit Executed(msg.sender, callId, _actions, execResults);

        return execResults;
    }

    function approveTokenTransfer(address _token, address _spender, uint256 _amount) external onlyManager trustedProtocol(_spender) {
        IERC20(_token).safeApprove(_spender, _amount);

    }

    function execute(
        address _target,
        uint256 _ethValue,
        bytes calldata _data // This function MUST always be external as the function performs a low level return, exiting the Agent app execution context
    ) external notEmergencyMode onlyManager trustedProtocol(_target) {
        decodeAndCall(_target, _ethValue, _data);

    }

    function directAssetTransfer(
        address _target,
        uint256 _ethValue,
        bytes calldata _data // This function MUST always be external as the function performs a low level return, exiting the Agent app execution context
    ) external notEmergencyMode {
        if (block.timestamp <= configuration.finishTime()) revert FundraisingInProgress();
        require(msg.sender == address(this) && configuration.canPerformDirectTransfer(), "Unauthorized call");
    
        if (!registry.isAspisSupportedTradingToken(_target)) {
            revert UnsupportedToken();
        }
        
        executeLowLevelCall(_target, _ethValue, _data);
    }

    function emergencyStop() external {
        if (msg.sender != guardian) revert NotGuardian();

        emergencyStopActivated = true;

        IAspisConfiguration(configuration).setRageQuitFee(0);

    }

    function decodeAndCall( 
        address _target,
        uint256 _ethValue,
        bytes calldata _data) internal {

        address _decoder = registry.getDecoder(_target);

        if(_decoder == address(0)) {
            revert("Decoder not supported yet");
        }

        (address srcToken, address desToken, , ,) = IAspisDecoder(_decoder).decodeExchangeInput(_data);        

        if (!configuration.supportsTradingToken(desToken)) {
            revert UnsupportedToken();
        }

        uint256 _srcTokenAmountBefore = getBalance(srcToken);
        uint256 _desTokenAmountBefore = getBalance(desToken);

        executeLowLevelCall(_target, _ethValue, _data);

        uint256 _srcTokenAmountAfter = getBalance(srcToken);
        uint256 _desTokenAmountAfter = getBalance(desToken);

        meetsSlippageTolerance(srcToken, desToken, _srcTokenAmountBefore - _srcTokenAmountAfter, _desTokenAmountAfter - _desTokenAmountBefore);

    }


    function executeLowLevelCall(
        address _target,
        uint256 _ethValue,
        bytes calldata _data
    ) internal {
        
        (bool result, ) = _target.call{value: _ethValue}(_data);

        assembly {
            let ptr := mload(0x40)
            returndatacopy(ptr, 0, returndatasize())

            // revert instead of invalid() bc if the underlying call failed with invalid() it already wasted gas.
            // if the call returned error data, forward it
            switch result
            case 0 {
                revert(ptr, returndatasize())
            }
        }
    }

    /// @dev ERC1271 implementation. We accept signatures for Permit2. However, in order to validate that spender is a trusted protocol we extend the signature
    /// to include permit data. Signature has the following format ("address", "uint160", "uint48", "uint48", "address", "uint256", "bytes")
    /// where last parameter is an actual message signed by the manager and others are permit data
    function isValidSignature(bytes32 _hash, bytes calldata _signature) external view returns (bytes4 magicValue) {
        (address _token, uint160 amount, uint48 expiration, uint48 nonce, address spender, uint256 deadline, bytes memory signature) =
            abi.decode(_signature, (address, uint160, uint48, uint48, address, uint256, bytes));

        if (!configuration.supportsProtocol(spender)) {
            revert InvalidSignature(1);
        }

        bytes32 permitHash = Permit2Lib.hashData(_token, amount, expiration, nonce, spender, deadline);
        if (permitHash != _hash) revert InvalidSignature(2);

        address signer = ECDSAExternal.recover(_hash, signature);
        if (signer != manager) revert InvalidSignature(3);

        return EIP1271_MAGIC_VALUE;
    }

    function validateProposal(bytes calldata _proposal, address _creator) public override view returns(bool) {

        if(emergencyStopActivated) {
            return false;
        }

        bytes4 selector = bytes4(_proposal[:4]);

        if(selector == PROPOSAL_BURN || selector == PROPOSAL_MINT) {
            return false;
        }
        
        return (
            (selector == PROPOSAL_UPDATE_MANAGER && configuration.canChangeManager())
            || selector == PROPOSAL_REMOVE_PROTOCOLS
            || selector == PROPOSAL_REMOVE_TRADING_TOKENS
            || _creator == manager
        );
    }

    function transferAsset(
        address[] memory _tokens,
        address _receiver,
        uint256 _amount,
        uint256 _tokenSupply
    ) internal {
        for (uint8 i = 0; i < _tokens.length; i++) {
            if (_tokens[i] == address(ETH)) {
                (bool ok, ) = _receiver.call{value: AspisLibrary.calculateProRataShare(getBalance(_tokens[i]), _amount, _tokenSupply)}("");
                if (!ok) revert ETHWithdrawFailed();
            } else {
                if (IERC20(_tokens[i]).balanceOf(address(this)) != 0) {
                    IERC20(_tokens[i]).safeTransfer(_receiver, AspisLibrary.calculateProRataShare(getBalance(_tokens[i]), _amount, _tokenSupply));
                }
            }
        }
    }

    function meetsSlippageTolerance(address srcToken,address desToken,uint256 inputAmount,uint256 outputAmount) internal {
        uint256 _srcTokenValue = calculator.convert(srcToken, inputAmount);
        uint256 _destTokenValue = calculator.convert(desToken, outputAmount);

        if(_srcTokenValue > _destTokenValue) {
            uint256 _slippage = ((_srcTokenValue - _destTokenValue) * 10000)/_srcTokenValue;

            if(_slippage > SLIPPAGE_TOLERANCE_PERCENTAGE) {
                revert TradeExceededSlippageTolerance();
            }
        }
    }


    /** 
    * @notice returns the current price of LP tokens of the DAO along with the USD pooled value of assets stored
    */
    function getCurrentTokenPrice(uint256 _tempETHBalance) internal returns (uint256 _price, uint256 _poolValue) {
        if (!hasUsedDeposit) {
            _price = configuration.initialPrice();
            return (_price, 0);
        } else {

            address[] memory _tokens = registry.getAspisSupportedTradingTokens();

            for (uint64 i = 0; i < _tokens.length; i++) {
                uint256 _balance = _tokens[i] == ETH
                    ? (address(this).balance) - _tempETHBalance
                    : IERC20(_tokens[i]).balanceOf(address(this));
                _poolValue += calculator.convert(_tokens[i], _balance);
            }

            // If pool value is 0 return DAO to initial state
            if(_poolValue <= 0) {
                return (configuration.initialPrice(), 0);
            }
            _price = (_poolValue * (10**token.decimals())) / getTokenSupply(); //1200/1000 = 1.2
            return (_price, _poolValue);
        }
    }

    /** 
    * @notice returns true if rage quit fee needs to be applied
    */
    function isRageQuitFeeRequired() internal view returns (bool) {

        uint256 _fundraisingFinishTime = configuration.finishTime();

        //rage quit fee applied if withdrawl within fund raising period
        if(AspisLibrary.isWithdrawalWithinFundraising(_fundraisingFinishTime)) {
            return true;
        }

        //rage quit fee applied if withdrawl outside of withdraw window
        if(!AspisLibrary.isWithdrawalWithinWindow(configuration.withdrawlWindow() * SUPPORTED_TIME_UNIT,  configuration.freezePeriod() * SUPPORTED_TIME_UNIT, _fundraisingFinishTime)) {
            return true;
        }

        return false;
    }

    function getTokenSupply() internal view returns (uint256) {
        return managerBalance + token.totalSupply();
    }

    function getBalance(address _token) internal view returns(uint256) {
        if(_token == ETH) {
            return address(this).balance;
        } else {
            return IERC20(_token).balanceOf(address(this));
        }
    }

    function validateDepositLimit(uint256 _depositValue, address _depositor) internal view {
        
        uint256 _currentDepositValue = _depositValue + worthOfUserAsset[_depositor];

        (uint256 _minDepositLimit, uint256 _maxDepositLimit) = configuration.getDepositLimit();
        
        if(_minDepositLimit > 0 && (_depositValue / (10**SUPPORTED_USD_DECIMALS)) < _minDepositLimit) {
            revert DepositLimitError();
        } 
        
        if(_maxDepositLimit != type(uint256).max && (_currentDepositValue / (10**SUPPORTED_USD_DECIMALS)) > _maxDepositLimit) {
            revert DepositLimitError();
        }
    }

    function getManager() public view override returns(address) {
        return manager;
    }

    function fundManagementFee() internal view returns(uint256) {
        return AspisLibrary.calculateFundManagementFee(block.timestamp, lastFundManagementFeeTimestamp, getTokenSupply(), configuration.fundManagementFee());
    }

}

