// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./ReentrancyGuard.sol";

import {Governable} from "./Governable.sol";
import {IVester} from "./IVester.sol";
import {IReserveFreeVester} from "./IReserveFreeVester.sol";

contract VesterRouter is ReentrancyGuard, Governable {
    address public immutable vesterNeu;
    address public immutable reserveFreeVester;

    mapping(address => bool) public isHandler;

    event Claim(address receiver, uint256 amount);
    event Deposit(address account, uint256 amount);
    event Withdraw(address account, uint256 claimedAmount, uint256 balance);

    constructor(
        address _vesterNeu,
        address _reserveFreeVester
    ) {
        vesterNeu = _vesterNeu;
        reserveFreeVester = _reserveFreeVester;
    }

    function setHandler(address _handler, bool _isActive) external onlyGov {
        isHandler[_handler] = _isActive;
    }

    function setHandlers(address[] memory _handler, bool[] memory _isActive) external onlyGov {
        for(uint256 i = 0; i < _handler.length; i++){
            isHandler[_handler[i]] = _isActive[i];
        }
    }

    function depositForAccountVesterNeu(address _account, uint256 _amount) external nonReentrant {
        _validateHandler();

        _deposit(_account, _amount);
    }

    function depositVesterNeu(uint256 _amount) external nonReentrant {
        _deposit(msg.sender, _amount);
    }

    function claimVesterNeu() external nonReentrant returns (uint256) {
        return _claim(msg.sender, msg.sender);
    }

    function claimForAccountVesterNeu(address _account, address _receiver) external nonReentrant returns (uint256) {
        _validateHandler();

        return _claim(_account, _receiver);
    }

    function _deposit(address _account, uint256 _amount) private {
        uint256 vestableAmount = IReserveFreeVester(reserveFreeVester).getMaxVestableAmount(_account);
        uint256 usedAmount = IReserveFreeVester(reserveFreeVester).usedAmounts(_account);

        uint256 availableReserveFreeAmount = vestableAmount - usedAmount;

        if (availableReserveFreeAmount == 0) {
            IVester(vesterNeu).depositForAccount(_account, _amount);
            return;
        }

        if(availableReserveFreeAmount >= _amount) {
            IReserveFreeVester(reserveFreeVester).depositForAccount(_account, _amount);
        } else {
            uint256 diff = _amount - availableReserveFreeAmount;

            IReserveFreeVester(reserveFreeVester).depositForAccount(_account, availableReserveFreeAmount);
            IVester(vesterNeu).depositForAccount(_account, diff);
        }
    }

    function _claim(address _account, address _receiver) private returns (uint256) {
        uint256 reserveFreeVesterAmount = IReserveFreeVester(reserveFreeVester).claimForAccount(_account, _receiver);
        uint256 neuVesterAmount = IVester(vesterNeu).claimForAccount(_account, _receiver);

        return reserveFreeVesterAmount + neuVesterAmount;
    }

    function _validateHandler() private view {
        require(isHandler[msg.sender], "Vester: forbidden");
    }
}
