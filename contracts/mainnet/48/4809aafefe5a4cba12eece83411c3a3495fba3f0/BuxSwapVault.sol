// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

contract BuxSwapVault is Ownable, ReentrancyGuard {
    error Paused();
    error NotEnoughInVault();
    error OnlyClaimer();
    error TokenNotEnabled();

    event Claimed(address account, uint256 amount);
    event Deposited(address account, address token, uint256 amount);

    address public claimer;
    bool public paused = false;
    mapping(address => bool) private supportedTokens;

    constructor(address _claimer) {
        claimer = _claimer;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    /// @dev check vault balance for a token, has to be a supported token
    function balanceOf(address token)
        public
        view
        virtual
        returns (uint256 balance)
    {
        if (!supportedTokens[token]) revert TokenNotEnabled();
        return IERC20(token).balanceOf(address(this));
    }

    /// @dev internal method to transfer any supported ERC20 token
    function _transfer(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        if (!supportedTokens[token]) revert TokenNotEnabled();
        IERC20(token).transferFrom(from, to, amount);
    }

    /////////////////////
    /// Token setting ///
    /////////////////////

    /// @dev enable/disable supported token
    function setSupportedToken(address token, bool enable) external onlyOwner {
        require(supportedTokens[token] != enable, "No difference");
        supportedTokens[token] = enable;
    }

    /// @dev check if a token is supported
    function isTokenSupported(address token) public view returns (bool) {
        return supportedTokens[token];
    }

    ///////////////
    /// Deposit ///
    ///////////////

    /// @dev desposit amount of token to address
    function deposit(address token, uint256 amount) external nonReentrant {
        if (paused) revert Paused();
        _transfer(token, _msgSender(), address(this), amount);
        emit Deposited(_msgSender(), token, amount);
    }

    ////////////////
    /// Claiming ///
    ////////////////

    /// @dev claim token, called from claimer contract only
    function claim(
        address to,
        address token,
        uint256 amount
    ) external {
        if (_msgSender() != claimer) revert OnlyClaimer();
        if (paused) revert Paused();
        if (!supportedTokens[token]) revert TokenNotEnabled();
        if (amount > balanceOf(token)) revert NotEnoughInVault();

        // approve & transfer token to user
        IERC20(token).approve(address(this), amount);
        _transfer(token, address(this), to, amount);
        emit Claimed(to, amount);
    }

    /// @dev set new claimer
    function setClaimer(address _claimer) external onlyOwner {
        claimer = _claimer;
    }

    ////////////////
    /// Withdraw ///
    ////////////////

    /// @dev withdraw any currency that gets mistakenly sent to this address
    function withdrawToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (!supportedTokens[token]) revert TokenNotEnabled();
        IERC20(token).approve(address(this), amount);
        _transfer(token, address(this), to, amount);
    }

    function withdraw() external onlyOwner {
        // withdraw all eth to owner
        require(address(this).balance > 0, "No balance to withdraw");
        (bool hs, ) = payable(owner()).call{value: address(this).balance}("");
        require(hs, "Withdraw failed");
    }

    ////////////////////
    /// ETH fallback ///
    ////////////////////

    receive() external payable {
        emit Deposited(
            _msgSender(),
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH contract
            msg.value
        );
    }

    /// @dev convenience method to get ETH balance
    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}

