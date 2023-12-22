// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./SafeERC20.sol";

contract FoxifyVestedNFT is Ownable, ERC721Enumerable {
    using SafeERC20 for IERC20;

    struct Wave {
        uint256 startTimestamp;
        IERC20 stableToken;
        uint256 stablePrice;
        uint256 startID;
        uint256 endID;
    }

    address public paymentsRecipient;
    uint256 public activeWaveIndex;
    mapping(uint256 => Wave) public waves;
    mapping(uint256 => uint256) public NFTWave;

    function availableToMint() external view returns (uint256) {
        return waves[activeWaveIndex].endID + 1 - totalSupply();
    }

    function activeWave() external view returns (Wave memory result) {
        result = waves[activeWaveIndex];
    }

    event MintingStarted(uint256 waveIndex, Wave data);
    event PaymentsRecipientUpdated(address paymentsRecipient);

    constructor (
        string memory name_,
        string memory symbol_,
        address paymentsRecipient_
    ) ERC721(name_, symbol_) {
        _updatePaymentsRecipient(paymentsRecipient_);
    }

    function mint(uint256 quantity) external returns (bool) {
        Wave storage wave = waves[activeWaveIndex];
        uint256 totalSupply_ = totalSupply();
        require(quantity > 0, "FoxifyVestedNFT: Quantity not positive");
        require(block.timestamp >= wave.startTimestamp, "FoxifyVestedNFT: Too early");
        require(totalSupply_ <= wave.endID, "FoxifyVestedNFT: Wave exhausted");
        require(totalSupply_ + quantity <= wave.endID, "FoxifyVestedNFT: Quantity gt wave endID");
        wave.stableToken.safeTransferFrom(msg.sender, paymentsRecipient, wave.stablePrice * quantity);
        for (uint256 i = 0; i < quantity; i++) {
            uint256 id = totalSupply_ + i;
            _safeMint(msg.sender, id);
            NFTWave[id] = activeWaveIndex;
        }
        return true;
    }

    function startMint(
        uint256 startTimestamp,
        uint256 count,
        uint256 stablePrice, 
        IERC20 stableToken_
    ) external onlyOwner returns (bool) {
        require(startTimestamp > block.timestamp, "FoxifyVestedNFT: Invalid startTimestamp");
        require(count > 0, "FoxifyVestedNFT: Count not positive");
        require(stablePrice > 0, "FoxifyVestedNFT: Price not positive");
        require(address(stableToken_) != address(0), "FoxifyVestedNFT: Stable token is zero address");
        uint256 totalSupply_ = totalSupply();
        if (activeWaveIndex > 0 || totalSupply_ > 0) {
            waves[activeWaveIndex].endID = totalSupply_ - 1;
            activeWaveIndex += 1;
        }
        Wave storage wave = waves[activeWaveIndex];
        wave.startTimestamp = startTimestamp;
        wave.stableToken = stableToken_;
        wave.stablePrice = stablePrice;
        wave.startID = totalSupply_;
        wave.endID = totalSupply_ + count - 1;
        emit MintingStarted(activeWaveIndex, wave);
        return true;
    }

    function updatePaymentsRecipient(address paymentsRecipient_) external onlyOwner returns (bool) {
        _updatePaymentsRecipient(paymentsRecipient_);
        return true;
    }

    function _updatePaymentsRecipient(address paymentsRecipient_) private {
        require(paymentsRecipient_ != address(0), "FoxifyVestedNFT: Payments recipient is zero address");
        paymentsRecipient = paymentsRecipient_;
        emit PaymentsRecipientUpdated(paymentsRecipient_);
    }
}

