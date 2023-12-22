// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./IVovoVault.sol";
import "./IGlpVault.sol";
import "./IStakedGlp.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

contract VaultRouter {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public ppvUpVault;
    address public ppvDownVault;
    address public ppvVaultToken;
    address public glpUpVault;
    address public glpDownVault;
    address public glpVaultToken;

    event DepositPPV(address indexed depositor, address indexed account, uint256 upVaultAmount, uint256 downVaultAmount);
    event DepositGlp(address indexed depositor, address indexed account, uint256 upVaultAmount, uint256 downVaultAmount);

    constructor(
        address _ppvUpVault,
        address _ppvDownVault,
        address _ppvVaultToken,
        address _glpUpVault,
        address _glpDownVault,
        address _glpVaultToken
    ) public {
        ppvUpVault = _ppvUpVault;
        ppvDownVault = _ppvDownVault;
        ppvVaultToken = _ppvVaultToken;
        glpUpVault = _glpUpVault;
        glpDownVault = _glpDownVault;
        glpVaultToken = _glpVaultToken;
    }

    function depositPPVFor(uint256 upVaultAmount, uint256 downVaultAmount, address account) external {
        IERC20(ppvVaultToken).safeTransferFrom(msg.sender, address(this), upVaultAmount.add(downVaultAmount));
        IERC20(ppvVaultToken).safeApprove(ppvUpVault, upVaultAmount);
        IERC20(ppvVaultToken).safeApprove(ppvDownVault, downVaultAmount);
        IVovoVault(ppvUpVault).depositFor(upVaultAmount, account);
        IVovoVault(ppvDownVault).depositFor(downVaultAmount, account);
        emit DepositPPV(msg.sender, account, upVaultAmount, downVaultAmount);
    }

    function depositGlpFor(uint256 upVaultAmount, uint256 downVaultAmount, address account) external {
        IStakedGlp(glpVaultToken).transferFrom(msg.sender, address(this), upVaultAmount.add(downVaultAmount));
        IERC20(glpVaultToken).approve(glpUpVault, upVaultAmount);
        IERC20(glpVaultToken).approve(glpDownVault, downVaultAmount);
        IGlpVault(glpUpVault).depositGlpFor(upVaultAmount, account);
        IGlpVault(glpDownVault).depositGlpFor(downVaultAmount, account);
        emit DepositGlp(msg.sender, account, upVaultAmount, downVaultAmount);
    }
}

