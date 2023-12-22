//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

// Website: https://arbitrumbook.io
// Twitter: https://twitter.com/ArbitrumBook
// Documentation: https://docs.arbitrumbook.io

//                                    %&&&/
//                                .&&&&&&&&&&/
//                             &&&&&&%%%%%%%&&&&/
//                         &&&&&&%%%%%%%%%%%%%%&&&%*
//                     *%%%&&%%%%%%%%%%%%%%%%%%%%%%%%%,
//                  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%&,
//              &&&&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#&&&&.
//          #&&&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%########&&&&.
//       &&&&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%###############&&&&
//   &&&&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#%#%############&&&&&&
//   &&&&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%#########&&&&&&//
//   &&&&*&&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%###%&&&&&#////**
//   &&&..,,/&&&%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%&&&////*****@
//   &&&&...,,*/%%%%%%%%%%%%%#####%%%%%%%%%%%%%%%%***/*****%&&&@@@@
//   &&&&&&%..,,**/%%%%%%#############%%%&&&&&**********&&&@@@@@@
//      &&&&%%%,,,,**/&&&&##########%&&&&&&(((#********@@@@@@
//         &&&&%%%,,,**/(&&&&####&&&&&&////**/(((**####@@.
//            &&&&%%&,,***/(&&&&&&&(///*****/&&&@######
//               &&&&&&&****///%////*****&&&@@@@@######
//                  @&@@&&&**********&&&@@@@@@   ##%%%%
//                     @@@@&&&***(&&&@@@@@(      %%%%%%
//                        @@@@&&&@@@@@@          %%%%%%
//                           @@@@@@              %

contract pBook is ERC20Burnable, Ownable {
    using SafeMath for uint256;

    address public presaleContract;

    constructor() ERC20("PresaleBook", "pBook") {}

    modifier onlyPresale() {
        require(msg.sender == presaleContract, "Only presale contract");
        _;
    }

    function setPresaleContract(address presaleContract_) external onlyOwner {
        require(presaleContract_ != address(0), "The address can not be 0");
        presaleContract = presaleContract_;
    }

    function mint(address _recipient, uint256 _amount) public onlyPresale {
        _mint(_recipient, _amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOwner {
        _token.transfer(_to, _amount);
    }
}

