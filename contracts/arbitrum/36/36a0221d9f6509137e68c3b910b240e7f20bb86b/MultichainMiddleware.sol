//SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

import {IGmxRewardRouter} from "./IGmxRewardRouter.sol";

import {WhitelistController} from "./WhitelistController.sol";

import {GlpAdapter} from "./GlpAdapter.sol";

contract MultichainMiddleware is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    address private constant deployer = 0xc8ce0aC725f914dBf1D743D51B6e222b79F479f1;

    IERC20 public constant jUSDC = IERC20(0xe66998533a1992ecE9eA99cDf47686F4fc8458E0);
    IERC20 public constant jGLP = IERC20(0x7241bC8035b65865156DDb5EdEf3eB32874a3AF6);

    IERC20 public constant glp = IERC20(0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf);
    IERC20 public constant usdc = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    IGmxRewardRouter public gmxRouter;
    address public socket;
    GlpAdapter public adapter;
    WhitelistController public controller;

    mapping(address => bool) public isValid;

    // INIT

    function initialize(address[] memory _tokens, address _controller, address _socket, address _adapter)
        external
        initializer
    {
        if (msg.sender != deployer) {
            revert InvalidInitializer();
        }

        __Ownable_init();
        __ReentrancyGuard_init();

        for (uint256 i = 0; i < _tokens.length;) {
            _editToken(_tokens[i], true);
            unchecked {
                i++;
            }
        }

        adapter = GlpAdapter(_adapter);
        controller = WhitelistController(_controller);
        socket = _socket;
        gmxRouter = IGmxRewardRouter(0xB95DB5B167D75e6d04227CfFFA61069348d271F5);
    }

    // MultiChain Deposits

    function multichainZapToGlp(address _receiver, address _token) external nonReentrant returns (uint256) {
        IERC20 token = IERC20(_token);

        uint256 amount = token.allowance(msg.sender, address(this));

        if (!isValid[_token]) {
            return 0;
        }

        token.transferFrom(msg.sender, address(this), amount);

        if (!_onlySocket()) {
            token.transfer(_receiver, amount);
            return 0;
        }

        if (!_onlyAllowed(_receiver)) {
            return 0;
        }

        address glpManager = gmxRouter.glpManager();
        token.approve(glpManager, amount);

        uint256 mintedGlp;

        try gmxRouter.mintAndStakeGlp(_token, amount, 0, 0) returns (uint256 glpAmount) {
            mintedGlp = glpAmount;
        } catch {
            token.transfer(_receiver, amount);
            token.safeDecreaseAllowance(glpManager, amount);
            return 0;
        }

        address adapterAddress = address(adapter);

        glp.approve(adapterAddress, mintedGlp);

        try adapter.depositGlp(mintedGlp, true) returns (uint256 receipts) {
            jGLP.transfer(_receiver, receipts);
            return receipts;
        } catch {
            glp.transfer(_receiver, mintedGlp);
            glp.approve(adapterAddress, 0);
            return 0;
        }
    }

    function multichainDepositGlp(address _receiver) external nonReentrant returns (uint256) {
        uint256 amount = glp.allowance(msg.sender, address(this));

        glp.transferFrom(msg.sender, address(this), amount);

        if (!_onlySocket()) {
            glp.transfer(_receiver, amount);
            return 0;
        }

        if (!_onlyAllowed(_receiver)) {
            return 0;
        }

        address adapterAddress = address(adapter);

        glp.approve(adapterAddress, amount);

        try adapter.depositGlp(amount, true) returns (uint256 receipts) {
            jGLP.transfer(_receiver, receipts);
            return receipts;
        } catch {
            glp.transfer(_receiver, amount);
            glp.approve(adapterAddress, 0);
            return 0;
        }
    }

    function multichainDepositStable(address _receiver) external nonReentrant returns (uint256) {
        uint256 amount = usdc.allowance(msg.sender, address(this));

        usdc.transferFrom(msg.sender, address(this), amount);

        if (!_onlySocket()) {
            usdc.transfer(_receiver, amount);
            return 0;
        }

        if (!_onlyAllowed(_receiver)) {
            return 0;
        }

        address adapterAddress = address(adapter);

        usdc.approve(adapterAddress, amount);

        try adapter.depositStable(amount, true) returns (uint256 receipts) {
            jUSDC.transfer(_receiver, receipts);
            return receipts;
        } catch {
            usdc.transfer(_receiver, amount);
            usdc.safeDecreaseAllowance(adapterAddress, amount);
            return 0;
        }
    }

    function rescueFunds(address _token, address _userAddress, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_userAddress, _amount);
    }

    function updateGmxRouter(address _gmxRouter) external onlyOwner {
        gmxRouter = IGmxRewardRouter(_gmxRouter);
    }

    function updateAdapter(address _adapter) external onlyOwner {
        adapter = GlpAdapter(_adapter);
    }

    function updateSocket(address _socket) external onlyOwner {
        socket = _socket;
    }

    function editToken(address _token, bool _valid) external onlyOwner {
        _editToken(_token, _valid);
    }

    function _editToken(address _token, bool _valid) private {
        isValid[_token] = _valid;
    }

    function _onlySocket() private view returns (bool) {
        if (msg.sender == socket) {
            return true;
        }
        return false;
    }

    function _onlyAllowed(address _receiver) private view returns (bool) {
        if (isContract(_receiver) && !controller.isWhitelistedContract(_receiver)) {
            return false;
        }
        return true;
    }

    function isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    modifier validToken(address _token) {
        require(isValid[_token], "Invalid token.");
        _;
    }

    error InvalidInitializer();
    error NotWhitelisted();
    error SendETHFail();
}

