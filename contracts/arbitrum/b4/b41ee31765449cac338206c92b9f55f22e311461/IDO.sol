// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./ReentrancyGuard.sol";
import { Governable } from "./Governable.sol";
import { IERC20 } from "./IERC20.sol";
import "./MerkleProof.sol";

contract IDO is ReentrancyGuard, Governable {
    uint256 constant PRECISION = 1000;

    bool public isDeposit;
    bool public isClaimToken;
    bool public isClaimWhitelistSale;
    bool public isClaimPublicSale;
    bool public isClaimRef;
    bool public isPublicSale;
    bool public isWhitelistSale;

    uint256 public maxAmountDeposit;
    uint256 public minAmountDeposit;
    uint256 public round1HardCap;
    uint256 public round2HardCap;
    uint256 public round3HardCap;
    uint256 public rate;
    uint256 public refPercent;

    uint256 public totalWhitelistDeposit;
    uint256 public totalPublicDeposit;
    uint256 public totalClaim;
    uint256 public totalWhitelistClaim;
    address public tokenSell;

    bytes32 public merkleRoot;

    mapping(address => uint256) public whitelistDepositUsers;
    mapping(address => mapping(uint256 => uint256)) public publicDepositUsers;
    mapping(address => address) public refUsers;
    mapping(address => uint256) public refCount;
    mapping(address => uint256) public refAmount;
    mapping(address => mapping(uint256 => bool)) public claimPublicTokenUsers;
    mapping(address => bool) public claimWhitelistTokenUsers;

    event Deposit(address indexed account, uint256 amount);
    event ClaimTokenSell(address indexed account, uint256 amount);
    event SetSale(bool isPublicSale, bool isWhitelistSale);

    constructor(address _tokenSell) {
      tokenSell = _tokenSell;
      maxAmountDeposit = 5 * 10 ** 18;
      minAmountDeposit = 5 * 10 ** 16;

      round1HardCap = 50 * 10 ** 18; // 50 ETH
      round2HardCap = 100 * 10 ** 18; // 100 ETH
      round3HardCap = 150 * 10 ** 18; // 150 ETH

      rate = 2000;
      refPercent = 30; // 3%
    }

    function setClaimStatus(bool _isClaimWhitelistSale, bool _isClaimPublicSale,  bool _isClaimRef) external onlyGov {
      isClaimWhitelistSale = _isClaimWhitelistSale;
      isClaimPublicSale = _isClaimPublicSale;
      isClaimRef = _isClaimRef;
    }

    function setSale(bool _isPublicSale, bool _isWhitelistSale) external onlyGov {
        isPublicSale = _isPublicSale;
        isWhitelistSale = _isWhitelistSale;
        emit SetSale(_isPublicSale, _isWhitelistSale);
    }
    
    function setTokens(address _tokenSell) external onlyGov {
      tokenSell = _tokenSell;
    }

    function setMaxAmountDeposit(uint256 _maxAmountDeposit, uint256 _minAmountDeposit) external onlyGov {
      maxAmountDeposit = _maxAmountDeposit;
      minAmountDeposit = _minAmountDeposit;
    }

    function setHardCap(uint256 _round1HardCap, uint256 _round2HardCap, uint256 _round3HardCap) external onlyGov {
      round1HardCap = _round1HardCap;
      round2HardCap = _round2HardCap;
      round3HardCap = _round3HardCap;
    }

    function setRefPercent(uint256 _percent) external onlyGov {
      refPercent = _percent;
    }

    function whitlelistDeposit(address _refAddress, bytes32[] calldata _merkleProf) external payable nonReentrant {
      require(isDeposit, "IDO: deposit not active");
      require(isWhitelistSale, "IDO: sale is closed");
      require(_verify(_merkleProf, msg.sender), "IDO: invalid proof");

      uint256 amount = msg.value;
      uint256 totalAmount = amount + totalWhitelistDeposit;
      
      require(totalAmount <= round1HardCap, "IDO: max hardcap round 1");
      require((whitelistDepositUsers[msg.sender] + amount) <= maxAmountDeposit, "IDO: max amount deposit per user");
      require(amount >= minAmountDeposit, "IDO: min amount deposit per user");

      whitelistDepositUsers[msg.sender] += amount;
      totalWhitelistDeposit += amount;

      // handle ref
      if (refUsers[msg.sender] == address(0) && _refAddress != address(msg.sender) && _refAddress != address(0)) {
        refUsers[msg.sender] = _refAddress;
        refCount[_refAddress] += 1;
        refAmount[_refAddress] += (amount * refPercent) / PRECISION;
      } else if (refUsers[msg.sender] != address(0)) {
        refAmount[refUsers[msg.sender]] += (amount * refPercent) / PRECISION;
      }

      emit Deposit(msg.sender, amount);
    }

    function publicDeposit(address _refAddress) external payable nonReentrant {
      require(isPublicSale, "IDO: sale is closed");

      uint256 amount = msg.value;
      uint256 totalAmount = amount + totalPublicDeposit;
      uint256 roundNumber = totalPublicDeposit >= round2HardCap ? 2 : 3;
      
      require(totalAmount <= (round2HardCap + round3HardCap), "IDO: max hardcap round 3");
      require((publicDepositUsers[msg.sender][roundNumber] + amount) <= maxAmountDeposit, "IDO: max amount deposit per user");
      require(amount >= minAmountDeposit, "IDO: min amount deposit per user");

      publicDepositUsers[msg.sender][roundNumber] += amount;
      totalPublicDeposit += amount;

      // handle ref
      if (refUsers[msg.sender] == address(0) && _refAddress != address(msg.sender) && _refAddress != address(0)) {
        refUsers[msg.sender] = _refAddress;
        refCount[_refAddress] += 1;
        refAmount[_refAddress] += (amount * refPercent) / PRECISION;
      } else if (refUsers[msg.sender] != address(0)) {
        refAmount[refUsers[msg.sender]] += (amount * refPercent) / PRECISION;
      }

      emit Deposit(msg.sender, amount);
    }

    function withDrawnFund(uint256 _amount) external onlyGov {
      _safeTransferETH(address(msg.sender), _amount);
    }

    function claimToken(uint256 _round) external nonReentrant {
      require(isClaimPublicSale, "IDO: claim token not active");
      require(!claimPublicTokenUsers[msg.sender][_round], "IDO: user already claim token");

      uint256 amountToken = publicDepositUsers[msg.sender][_round] * rate;

      if (amountToken > 0) {
        IERC20(tokenSell).transfer(msg.sender, amountToken);
        totalClaim += amountToken;
      }

      claimPublicTokenUsers[msg.sender][_round] = true;

      emit ClaimTokenSell(msg.sender, amountToken);
    }

    function claimRef() external nonReentrant {
      require(isClaimRef, "IDO: claim ref not active");

      if (refAmount[msg.sender] > 0) {
        _safeTransferETH(address(msg.sender), refAmount[msg.sender]);
        refAmount[msg.sender] = 0;
      }
    }

    function whitelistClaimToken() external nonReentrant {
      require(isClaimWhitelistSale, "IDO: claim whitelist token not active");
      require(!claimWhitelistTokenUsers[msg.sender], "IDO: user already claim token");

      uint256 amountToken = whitelistDepositUsers[msg.sender] * rate;

      if (amountToken > 0) {
        IERC20(tokenSell).transfer(msg.sender, amountToken);
        totalWhitelistClaim += amountToken;
      }

      claimWhitelistTokenUsers[msg.sender] = true;

      emit ClaimTokenSell(msg.sender, amountToken);
    }

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success, "TransferHelper: ETH_TRANSFER_FAILED");
    }

    /**
     * @notice Allows the owner to recover tokens sent to the contract by mistake
     * @param _token: token address
     * @dev Callable by owner
     */
    function recoverFungibleTokens(address _token) external onlyGov {
        uint256 amountToRecover = IERC20(_token).balanceOf(address(this));
        require(amountToRecover != 0, "Operations: No token to recover");

        IERC20(_token).transfer(address(msg.sender), amountToRecover);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyGov {
        merkleRoot =  _merkleRoot;
    }

    function _verify(bytes32[] calldata _merkleProof, address _sender) private view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(_sender));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
    }
}
