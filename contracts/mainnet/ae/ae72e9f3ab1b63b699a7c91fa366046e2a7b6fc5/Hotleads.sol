//                .*(%%&&&@@@@@@@@@@@@@@@@@@@@@&&%#*
//                 *(&&@@@@@@&&%%#//***,.          ..*/#%&@@@@@@%(,
//               (@@@&#,     .*(#%%%&&&&&&@@&&&@@&&&%#/,    ./%&@@@@&(.
//               #@&* /&&&&@@&*./&@/ .%, ,&%  *&(  #@&//&@&&%(,   ,#&@@@&(.
//               ,&@&.,&&,  /@@,  .%/ .%#  (, ,&&, ,&&,  %@@@@%#&&&(.  .(&@@&,
//               /@@% /&#    (&(      .&&,    %@#  #@(  #@@@@(  /@@@%&&%*  ,&@&*
//              .%@@/.%&* ,(  (%. /   .&@#   (@&, ,&%. /@@@@(  (@@&*    (&*.%@@#.
//              ,&@&.,&%.      /  *%*  #@&/*#&@%..(&*  ./&&/  #@@&,  #&%&# .&@&*
//              (@@# (&%..%@@#*(&@@@@@@@@@@@@@@@@@@@@@&#(&(   *%&.  .,&@&, (@@#
//             .%@&..%@@@@&%###%@@@@@@@@@@@@@@&%/,,*#&@@@@@@&#/#*  .#@@@/ ,&@&,
//             *&@# /&@@#        .%&&*     /*.  ,%/   .&@@@@@@@@@@%//&@%  %@@%
//             /@@* #@@@@@@@@@@*     (&&/   ##   **      .      /&@@@@&, /@@@*
//             (@&, %@@@/  *%&%.  *%(.  .*#&@@@&#/**/%&%  *&@&%   #@@@( .&@@#.
//             /@%.,&@@@&%.   .,*%@@@@@@@@@@@@@@@@@@@@@%  .%@@@@%#%@@&. (@@&* ..
//             #@% .&@@@@@@@@@@@@@@@@@&&&&&@@@@@@&@@@@@@&,    .%@@@@&* ,&@@(
//             #@% .&@@@@&#....,*/%&@@@@@@&%###%&@@@@@@@@@@&&&&&@@@@#  %@@%
//             #@% .%@@@@&,          /&@@@%        .#@@@@&&&&&&&@@@#  %@@%.
//             (@&. #@@@@&,   (@@%.   .&@@/   ,(*     %@@&&&&&&@@&#  %@@%
//             (@@( ,&@@@&,   (@@@&,   (@%    %@@@/   .%@@@&&&@@&/  %@@(
//             ,&@&. #@@@&*   /@@@/    %&*   /@@@@&.   #@@@@@@@%. *&@@*
//              #@@# .%@@@#          .&@(   .&@@@@#    %@@@@@&/  %@@#
//              ,&@@/ .&@@&.      ,#@@@#    %@@@@#    (@@@@&(  /&@&.
//               *&@&/ ,&@@(   ,&@@@@@&.   (@@&(    .%@@@&*  (@@&.
//                /@@&* ,&@&,   /&@@@&*   *%(.    .%@@&(  .%@@%.
//                 /@@@/ .&@%.   #@@@(         .#@@@#.  (@@@(
//                  ,&@@#  %@#   ,&@&/     ,(&@@@&,  *&@@%,
//                    #@@&, ,&@@@@@@@@@@@@@@@@&/  .%@@%,
//                     ,&@@#  /&@@@@@&@@@@@&/   #@@%,
//                       ,&@@/  /&@@@@@@&/   (@@#.
//                         .%@&*  /&@&/  .(&&/
//                            #@&/     (&%,
//                              *&&%%&(.
pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./ECDSA.sol";
import "./ReentrancyGuard.sol";
import "./IERC721Receiver.sol";

interface ICrimereports {
    function balanceOf(address _address) external view returns (uint256);

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes memory data
    ) external;

    function getOwnedCrimes(address _owner) external returns (uint256[] memory);
}

contract Hotleads is Ownable, ReentrancyGuard, IERC721Receiver {
    address private VAULT;
    address private SIGNER;
    mapping(bytes => uint256) private usedSignaturesCounter;
    uint256 mintPrice = 333000000000000000;
    bool public opened;
    ICrimereports private CRIMEREPORTS;

    function commitACrime(bytes memory _sig) external payable nonReentrant {
        require(opened || msg.sender == owner(), "Not opened");
        require(CRIMEREPORTS.balanceOf(address(this)) > 0, "No more...");
        require(msg.value == mintPrice, "Not exact ETH");
        require(_recoverSigner(msg.sender, _sig) == SIGNER, "Not on allowlist");
        require(usedSignaturesCounter[_sig] < 2, "Signature used");
        usedSignaturesCounter[_sig]++;

        uint256 id = CRIMEREPORTS.getOwnedCrimes(address(this))[0];
        CRIMEREPORTS.safeTransferFrom(address(this), msg.sender, id, "");
    }

    function _recoverSigner(address _toCheck, bytes memory signature)
        internal
        pure
        returns (address)
    {
        bytes32 messageDigest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encodePacked(_toCheck))
            )
        );
        return ECDSA.recover(messageDigest, signature);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function pacify() external onlyOwner {
        uint256 balance = CRIMEREPORTS.balanceOf(address(this));
        for (uint256 i = 0; i < balance; i++) {
            uint256 id = CRIMEREPORTS.getOwnedCrimes(address(this))[0];
            CRIMEREPORTS.safeTransferFrom(address(this), VAULT, id, "");
        }
    }

    function setAddresses(
        address _crimeReports,
        address _vault,
        address _signer
    ) external onlyOwner {
        CRIMEREPORTS = ICrimereports(_crimeReports);
        VAULT = _vault;
        SIGNER = _signer;
    }

    function setPrice(uint256 _newPrice) external onlyOwner {
        mintPrice = _newPrice;
    }

    function setOpened(bool _flag) external onlyOwner {
        opened = _flag;
    }

    function withdraw() external onlyOwner {
        require(VAULT != address(0), "no vault");
        require(payable(VAULT).send(address(this).balance));
    }
}

