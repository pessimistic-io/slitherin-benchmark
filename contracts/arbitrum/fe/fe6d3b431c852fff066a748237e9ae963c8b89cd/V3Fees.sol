// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./Ownable.sol";
import "./SafeERC20.sol";

contract V3Fees is Ownable {
    using SafeERC20 for IERC20;

    address[] public tokens;

    uint256 public algebraCut = 30; // 30%

    address public treasury = 0x2660F4F8314356aB3F7e2Da745D5D4C786C486dd;
    address public algebra = 0x1d8b6fA722230153BE08C4Fa4Aa4B4c7cd01A95a;

    event FeeCollected(
        address indexed token,
        uint256 amount,
        address indexed recipient
    );

    constructor(address[] memory _tokens) {
        tokens = _tokens;
    }

    function collectFees() external {
        uint256 length = tokens.length;
        address[] memory tokensLocal = tokens;
        for (uint256 i = 0; i < length; ) {
            address token = tokensLocal[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                uint256 algebraFee = (balance * algebraCut) / 100;
                uint256 treasuryFee = balance - algebraFee;
                IERC20(token).safeTransfer(algebra, algebraFee);
                IERC20(token).safeTransfer(treasury, treasuryFee);
                emit FeeCollected(token, algebraFee, algebra);
                emit FeeCollected(token, treasuryFee, treasury);
            }
            unchecked {
                ++i;
            }
        }
    }

    function addToken(address token) external onlyOwner {
        tokens.push(token);
    }

    function removeToken(address token) external onlyOwner {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ) {
            if (tokens[i] == token) {
                tokens[i] = tokens[length - 1];
                tokens.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    function setTokens(address[] calldata _tokens) external onlyOwner {
        tokens = _tokens;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Treasury cannot be zero address");
        treasury = _treasury;
    }

    function setAlgebra(address _algebra) external onlyOwner {
        require(_algebra != address(0), "Algebra cannot be zero address");
        algebra = _algebra;
    }

    function setAlgebraCut(uint256 _algebraCut) external onlyOwner {
        require(_algebraCut <= 100, "Algebra cut too high");
        algebraCut = _algebraCut;
    }

    function withdrawTokens(address[] calldata _tokens) external onlyOwner {
        uint256 length = _tokens.length;
        for (uint256 i = 0; i < length; ) {
            IERC20(_tokens[i]).safeTransfer(
                msg.sender,
                IERC20(_tokens[i]).balanceOf(address(this))
            );
            unchecked {
                ++i;
            }
        }
    }

    function withdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}

