// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";


import "./IFOInitializable.sol";

contract IFODeployer is Ownable {
    using SafeERC20 for IERC20;
    uint256 public constant MAX_BUFFER_BLOCKS = 200000; // 200,000 blocks (6-7 days on BSC)
    event AdminTokenRecovery(address indexed tokenRecovered, uint256 amount);
    event NewIFOContract(address indexed ifoAddress);

    constructor() public {
        // pancakeProfile = _pancakeProfile;
    }

    function createIFO(
        address _lpToken,
        address _offeringToken,
        uint256 _startBlock,
        uint256 _endBlock,
        address _adminAddress
    ) external onlyOwner {
        require(IERC20(_lpToken).totalSupply() >= 0);
        require(IERC20(_offeringToken).totalSupply() >= 0);
        require(_lpToken != _offeringToken, "Operations: Tokens must be be different");
        require(_endBlock < (ARBSYS(100).arbBlockNumber() + MAX_BUFFER_BLOCKS), "Operations: EndBlock too far");
        require(_startBlock < _endBlock, "Operations: StartBlock must be inferior to endBlock");
        require(_startBlock > ARBSYS(100).arbBlockNumber(), "Operations: StartBlock must be greater than current block");

        bytes memory bytecode = type(IFOInitializable).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_lpToken, _offeringToken, _startBlock));
        address ifoAddress;

        assembly {
            ifoAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        IFOInitializable(ifoAddress).initialize(
            _lpToken,
            _offeringToken,
            // pancakeProfile,
            _startBlock,
            _endBlock,
            MAX_BUFFER_BLOCKS,
            _adminAddress
        );

        emit NewIFOContract(ifoAddress);
    }

    function recoverWrongTokens(address _tokenAddress) external onlyOwner {
        uint256 balanceToRecover = IERC20(_tokenAddress).balanceOf(address(this));
        require(balanceToRecover > 0, "Operations: Balance must be > 0");
        IERC20(_tokenAddress).safeTransfer(address(msg.sender), balanceToRecover);

        emit AdminTokenRecovery(_tokenAddress, balanceToRecover);
    }
}


