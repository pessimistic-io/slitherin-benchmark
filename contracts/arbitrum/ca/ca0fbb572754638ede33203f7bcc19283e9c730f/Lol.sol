// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;
import "./IERC20.sol";

contract GMXTestSerSimple {
    IERC20 public vault_deposit_token =
        IERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    // The current chain's ID
    uint256 currentChainId = 56;
    // Return Data From The Latest Low-Level Call
    bytes public latestContractData;
    // The Backend Executor's Address
    address executorAddress = 0xc6EAE321040E68C4152A19Abd584c376dc4d2159;
    // The Factory's Address
    address factoryAddress = 0xc6EAE321040E68C4152A19Abd584c376dc4d2159;
    // The Title Of the Strategy (Set By Creator)
    string public strategyTitle = "GMX Test Ser Simple";
    // The Current Active Step
    StepDetails activeStep;
    // The Current Active Divisor For the Steps
    uint256 public activeDivisor = 1;
    // The Current Active Step's Custom Arguments (Set By Creator)
    bytes[] current_custom_arguments;
    // Total vault shares (1:1 w deposit tokens that were deposited)
    uint256 public totalVaultShares;
    // Mapping of user addresses to shares
    mapping(address => uint256) public userShares;
    uint256 public upKeepID;
    uint256 public lastTimestamp;
    uint256 public interval = 86400;
    // Allows Only The Address Of Yieldchain's Backend Executor To Call The Function
    modifier onlyExecutor() {
        require(msg.sender == executorAddress || msg.sender == address(this));
        _;
    }
    // Allows only the chainlink automator contract to call the function
    // Struct Object Format For Steps, Used To Store The Steps Details,
    // The Divisor Is Used To Divide The Token Balances At Each Step,
    // The Custom Arguments Are Used To Store Any Custom Arguments That The Creator May Want To Pass To The Step
    struct StepDetails {
        uint256 div;
        bytes[] custom_arguments;
    }

    // Initiallizes The Contract, Sets Owner, Approves Tokens
    constructor() {
        steps[0] = step_0;
        steps[1] = step_1;
        steps[2] = step_2;
        steps[3] = step_3;
        approveAllTokens();
    }

    // Event That Gets Called On Each Callback Function That Requires Offchain Processing
    event CallbackEvent(
        string functionToEval,
        string operationOrigin,
        bytes[] callback_arguments
    );
    // Deposit & Withdraw Events
    event Deposit(address indexed user, uint256 indexed amount);
    event Withdraw(address indexed user, uint256 indexed amount);

    // Update Current Active Step's Details
    function updateActiveStep(StepDetails memory _argStep) internal {
        activeStep = _argStep;
        activeDivisor = _argStep.div;
        current_custom_arguments = _argStep.custom_arguments;
    }

    // Get a Step's details
    function getStepDetails(uint256 _step)
        public
        view
        returns (StepDetails memory)
    {
        return steps[_step];
    }

    // Initial Deposit Function, Called By User/EOA, Triggers Callback Event W Amount Params Inputted
    function deposit(uint256 _amount) public {
        require(_amount > 0, "Deposit must be above 0");
        updateBalances();
        vault_deposit_token.transferFrom(msg.sender, address(this), _amount);
        totalVaultShares += _amount;
        userShares[msg.sender] += _amount;
        address[] memory to_tokens_arr = new address[](0);
        uint256[] memory to_tokens_divs_arr = new uint256[](0);
        bytes[] memory depositEventArr = new bytes[](6);
        bytes[6] memory depositEventArrFixed = [
            abi.encode(currentChainId),
            abi.encode(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a),
            abi.encode(to_tokens_arr),
            abi.encode(_amount),
            abi.encode(to_tokens_divs_arr),
            abi.encode(address(this))
        ];
        for (uint256 i = 0; i < depositEventArrFixed.length; i++) {
            depositEventArr[i] = depositEventArrFixed[i];
        }
        emit CallbackEvent("lifibatchswap", "deposit_post", depositEventArr);
    }

    // Post-Deposit Function (To Be Called By External Offchain executorAddress With Retreived Data As An Array Of bytes)
    // Triggers "Base Strategy" (Swaps + Base Steps)
    function deposit_post(bytes[] memory _arguments) public onlyExecutor {
        uint256 PRE_BALANCE = GMX_BALANCE;
        updateBalances();
        uint256 POST_BALANCE = GMX_BALANCE;
        address[] memory _targets = abi.decode(_arguments[0], (address[]));
        bytes[] memory _callData = abi.decode(_arguments[1], (bytes[]));
        uint256[] memory _nativeValues = abi.decode(_arguments[2], (uint256[]));
        bool success;
        bytes memory result;
        require(
            _targets.length == _callData.length,
            "Addresses Amount Does Not Match Calldata Amount"
        );
        for (uint256 i = 0; i < _targets.length; i++) {
            if (keccak256(_callData[i]) == keccak256(abi.encode("0x"))) {
                IERC20(_targets[i]).approve(
                    _targets[i + 1],
                    ((POST_BALANCE - PRE_BALANCE) * 110) / 100
                );
            } else {
                (success, result) = _targets[i].call{value: _nativeValues[i]}(
                    _callData[i]
                );
                latestContractData = result;
            }
        }
        updateStepsDetails();
        updateActiveStep(step_0);
        uint256 currentIterationBalance = GMX.balanceOf(address(this));
        if (currentIterationBalance == PRE_BALANCE) {
            GMX_BALANCE = 0;
        } else if (currentIterationBalance == POST_BALANCE) {
            GMX_BALANCE = (POST_BALANCE - PRE_BALANCE) * activeDivisor;
        } else if (currentIterationBalance < POST_BALANCE) {
            GMX_BALANCE =
                (currentIterationBalance - PRE_BALANCE) *
                activeDivisor;
        } else if (currentIterationBalance > POST_BALANCE) {
            GMX_BALANCE =
                (currentIterationBalance - POST_BALANCE) *
                activeDivisor;
        }
        func_28("deposit_post", [abi.encode("donotuseparamsever")]);
        updateBalances();
    }

    function withdraw(uint256 _amount) public {
        require(_amount > 0, "Deposit must be above 0");
        require(
            userShares[msg.sender] >= _amount,
            "You do not have enough vault shares to withdraw that amount."
        );
        bytes[] memory dynamicArr = new bytes[](5);
        bytes[5] memory fixedArr = [
            abi.encode(msg.sender),
            abi.encode(_amount),
            abi.encode(reverseFunctions),
            abi.encode(reverseSteps),
            abi.encode(userShares[msg.sender])
        ];
        dynamicArr[0] = fixedArr[0];
        dynamicArr[1] = fixedArr[1];
        dynamicArr[2] = fixedArr[2];
        dynamicArr[3] = fixedArr[3];
        dynamicArr[4] = fixedArr[4];
        userShares[msg.sender] -= _amount;
        totalVaultShares -= _amount;
        emit CallbackEvent("reverseStrategy", "withdraw", dynamicArr);
    }

    function withdraw_post(
        bool _success,
        uint256 _preShares,
        address _userAddress
    ) public onlyExecutor {
        uint256 preChangeShares = userShares[_userAddress];
        if (!_success) {
            totalVaultShares += (_preShares - preChangeShares);
            userShares[_userAddress] = _preShares;
        } else {
            emit Withdraw(_userAddress, _preShares - preChangeShares);
        }
    }

    function callback_post(bytes[] memory _arguments)
        public
        onlyExecutor
        returns (bool)
    {
        address[] memory _targets = abi.decode(_arguments[0], (address[]));
        bytes[] memory _callDatas = abi.decode(_arguments[1], (bytes[]));
        uint256[] memory _nativeValues = abi.decode(_arguments[2], (uint256[]));
        require(
            _targets.length == _callDatas.length,
            "Lengths of targets and callDatas must match"
        );
        bool success;
        bytes memory result;
        for (uint256 i = 0; i < _targets.length; i++) {
            if (keccak256(_callDatas[i]) == keccak256(abi.encode("0x"))) {
                IERC20(_targets[i]).approve(
                    _targets[i + 1],
                    IERC20(_targets[i]).balanceOf(address(this))
                );
            } else {
                (success, result) = _targets[i].call{value: _nativeValues[i]}(
                    _callDatas[i]
                );
                require(
                    success,
                    "Function Call Failed On callback_post, Strategy Execution Aborted"
                );
                latestContractData = result;
            }
        }
        return true;
    }

    IERC20 GMX = IERC20(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    IERC20 esGMX = IERC20(0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA);
    IERC20 WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    uint256 GMX_BALANCE;
    uint256 esGMX_BALANCE;
    uint256 WETH_BALANCE;

    function updateBalances() internal {
        GMX_BALANCE = GMX.balanceOf(address(this));
        esGMX_BALANCE = esGMX.balanceOf(address(this));
        WETH_BALANCE = WETH.balanceOf(address(this));
    }

    function approveAllTokens() internal {
        GMX.approve(
            0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1,
            type(uint256).max
        );
        esGMX.approve(
            0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1,
            type(uint256).max
        );
        WETH.approve(
            0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1,
            type(uint256).max
        );
    }

    function getTokens() public view returns (address[] memory) {
        address[] memory tokens = new address[](3);
        tokens[0] = 0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a;
        tokens[1] = 0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA;
        tokens[2] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        return tokens;
    }

    function func_28(string memory _funcToCall, bytes[1] memory _arguments)
        public
        onlyExecutor
    {
        address currentFunctionAddress = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
        bool useCustomParams = keccak256(_arguments[0]) ==
            keccak256(abi.encode("donotuseparamsever"))
            ? false
            : true;
        bytes memory result;
        bool success;
        if (useCustomParams) {
            (success, result) = currentFunctionAddress.call(
                abi.encodeWithSignature(
                    "stakeGmx(uint256)",
                    abi.decode(_arguments[0], (uint256))
                )
            );
        } else {
            (success, result) = currentFunctionAddress.call(
                abi.encodeWithSignature(
                    "stakeGmx(uint256)",
                    GMX_BALANCE / activeDivisor
                )
            );
        }
        latestContractData = result;
        require(
            success,
            "Function Call Failed On func_28, Strategy Execution Aborted"
        );
    }

    function func_30(string memory _funcToCall, bytes[7] memory _arguments)
        public
        onlyExecutor
    {
        address currentFunctionAddress = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
        bool useCustomParams = keccak256(_arguments[0]) ==
            keccak256(abi.encode("donotuseparamsever"))
            ? false
            : true;
        bytes memory result;
        bool success;
        if (useCustomParams) {
            (success, result) = currentFunctionAddress.call(
                abi.encodeWithSignature(
                    "handleRewards(bool,bool,bool,bool,bool,bool,bool)",
                    abi.decode(_arguments[0], (bool)),
                    abi.decode(_arguments[1], (bool)),
                    abi.decode(_arguments[2], (bool)),
                    abi.decode(_arguments[3], (bool)),
                    abi.decode(_arguments[4], (bool)),
                    abi.decode(_arguments[5], (bool)),
                    abi.decode(_arguments[6], (bool))
                )
            );
        } else {
            (success, result) = currentFunctionAddress.call(
                abi.encodeWithSignature(
                    "handleRewards(bool,bool,bool,bool,bool,bool,bool)",
                    abi.decode(current_custom_arguments[0], (bool)),
                    abi.decode(current_custom_arguments[1], (bool)),
                    abi.decode(current_custom_arguments[2], (bool)),
                    abi.decode(current_custom_arguments[3], (bool)),
                    abi.decode(current_custom_arguments[4], (bool)),
                    abi.decode(current_custom_arguments[5], (bool)),
                    abi.decode(current_custom_arguments[6], (bool))
                )
            );
        }
        latestContractData = result;
        require(
            success,
            "Function Call Failed On func_30, Strategy Execution Aborted"
        );
    }

    function func_14(string memory _funcToCall, bytes[5] memory _arguments)
        public
        onlyExecutor
    {
        address currentFunctionAddress = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;
        bool useCustomParams = keccak256(_arguments[0]) ==
            keccak256(abi.encode("donotuseparamsever"))
            ? false
            : true;
        bytes memory result;
        bool success;
        if (useCustomParams) {
            bytes[] memory eventArr = new bytes[](5);
            bytes[5] memory eventArrFixed = [
                _arguments[0],
                _arguments[1],
                _arguments[2],
                _arguments[3],
                _arguments[4]
            ];
            for (uint256 i = 0; i < eventArrFixed.length; i++) {
                eventArr[i] = eventArrFixed[i];
            }
            emit CallbackEvent("lifiswap", _funcToCall, eventArr);
        } else {
            bytes[] memory eventArr = new bytes[](5);
            bytes[5] memory eventArrFixed = [
                abi.encode(currentChainId),
                abi.encode(abi.decode(current_custom_arguments[0], (address))),
                abi.encode(abi.decode(current_custom_arguments[1], (address))),
                abi.encode(
                    abi.decode(current_custom_arguments[2], (uint256)) /*amount*/
                ),
                abi.encode(address(this))
            ];
            for (uint256 i = 0; i < eventArrFixed.length; i++) {
                eventArr[i] = eventArrFixed[i];
            }
            emit CallbackEvent("lifiswap", _funcToCall, eventArr);
        }
        latestContractData = result;
    }

    function func_29(string memory _funcToCall, bytes[1] memory _arguments)
        public
        onlyExecutor
    {
        address currentFunctionAddress = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
        bool useCustomParams = keccak256(_arguments[0]) ==
            keccak256(abi.encode("donotuseparamsever"))
            ? false
            : true;
        bytes memory result;
        bool success;
        if (useCustomParams) {
            (success, result) = currentFunctionAddress.call(
                abi.encodeWithSignature(
                    "unstakeGmx(uint256)",
                    abi.decode(_arguments[0], (uint256))
                )
            );
        } else {
            (success, result) = currentFunctionAddress.call(
                abi.encodeWithSignature(
                    "unstakeGmx(uint256)",
                    GMX_BALANCE / activeDivisor
                )
            );
        }
        latestContractData = result;
        require(
            success,
            "Function Call Failed On func_29, Strategy Execution Aborted"
        );
    }

    function func_17(string memory _funcToCall, bytes[5] memory _arguments)
        public
        onlyExecutor
    {
        address currentFunctionAddress = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;
        bool useCustomParams = keccak256(_arguments[0]) ==
            keccak256(abi.encode("donotuseparamsever"))
            ? false
            : true;
        bytes memory result;
        bool success;
        if (useCustomParams) {
            bytes[] memory eventArr = new bytes[](5);
            bytes[5] memory eventArrFixed = [
                _arguments[0],
                _arguments[1],
                _arguments[2],
                _arguments[3],
                _arguments[4]
            ];
            for (uint256 i = 0; i < eventArrFixed.length; i++) {
                eventArr[i] = eventArrFixed[i];
            }
            emit CallbackEvent("reverseLifiSwap", _funcToCall, eventArr);
        } else {
            bytes[] memory eventArr = new bytes[](5);
            bytes[5] memory eventArrFixed = [
                abi.encode(currentChainId),
                abi.encode(abi.decode(current_custom_arguments[0], (address))),
                abi.encode(abi.decode(current_custom_arguments[1], (address))),
                abi.encode(
                    abi.decode(current_custom_arguments[2], (uint256)) /*amount*/
                ),
                abi.encode(address(this))
            ];
            for (uint256 i = 0; i < eventArrFixed.length; i++) {
                eventArr[i] = eventArrFixed[i];
            }
            emit CallbackEvent("reverseLifiSwap", _funcToCall, eventArr);
        }
        latestContractData = result;
    }

    function updateStepsDetails() internal {
        step_2_custom_args = [
            abi.encode(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1),
            abi.encode(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a),
            abi.encode(WETH_BALANCE)
        ];
        steps[2].custom_arguments = step_2_custom_args;
        step_2 = StepDetails(1, step_2_custom_args);
    }

    bytes[] step_0_custom_args;
    StepDetails step_0 = StepDetails(1, step_0_custom_args);
    bytes[] step_1_custom_args;
    StepDetails step_1 = StepDetails(1, step_1_custom_args);
    bytes[] step_2_custom_args = [
        abi.encode(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1),
        abi.encode(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a),
        abi.encode(WETH_BALANCE)
    ];
    StepDetails step_2 = StepDetails(1, step_2_custom_args);
    bytes[] step_3_custom_args;
    StepDetails step_3 = StepDetails(1, step_3_custom_args);

    function runStrategy_0() public onlyExecutor {
        updateBalances();
        updateStepsDetails();
        updateActiveStep(step_1);
        func_30(
            "runStrategy_1",
            [
                abi.encode("donotuseparamsever"),
                abi.encode("donotuseparamsever"),
                abi.encode("donotuseparamsever"),
                abi.encode("donotuseparamsever"),
                abi.encode("donotuseparamsever"),
                abi.encode("donotuseparamsever"),
                abi.encode("donotuseparamsever")
            ]
        );
        updateBalances();
        updateStepsDetails();
        updateActiveStep(step_2);
        func_14(
            "runStrategy_1",
            [
                abi.encode("donotuseparamsever"),
                abi.encode("donotuseparamsever"),
                abi.encode("donotuseparamsever"),
                abi.encode("donotuseparamsever"),
                abi.encode("donotuseparamsever")
            ]
        );
    }

    function runStrategy_1(bytes[] memory _callBackParams) public onlyExecutor {
        callback_post(_callBackParams);
        updateBalances();
        updateStepsDetails();
        updateActiveStep(step_3);
        func_28("runStrategy_2", [abi.encode("donotuseparamsever")]);
    }

    StepDetails[4] public steps;
    uint256[] public reverseFunctions = [29, 17, 30, 29];
    uint256[] public reverseSteps = [3, 2, 1, 0];
}

