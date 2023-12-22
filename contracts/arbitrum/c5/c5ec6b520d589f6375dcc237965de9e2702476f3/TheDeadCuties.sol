pragma solidity ^0.8.0;

import "./ERC721Enumerable.sol";
import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";

/*                                                                                                                  
                                                                                           
                                         '   ;;                                            
                                      '';-';;;~;;  ;;                                      
                                      ;;|;;|}}}}}--~~;';'                                  
                                 ;~;;;~|||||}}}}}|-~--;;;-;; ;                             
                                ;~~||||||||||}}}}}||||~~~~;                                
                              ;-~|||||||||||||}}}}||||||||-  ''                            
                              ''~|||||||||||||}}}}|||||||||~~||--;;                        
                             ;|}}}|||||||////+++++|||||||||||||~;;'                        
                         ;;~-|}}}}}}}|}++|-;;;;;;;++/|||||||||||~'                         
                         ~~-~||||}}/++~''''''''  '''-++/|||||||||;  '                      
                       ';~||||||||/|;'                '-/}|||||||-'  ';                    
                    ';--|~||||||}=-'                   ''+/||||}}}|-;                      
                    ;||||||||||}}}'       '''''''   '''''|}}|}}}}}}}}~;~;                  
                    ~||~|||||||+}''       '''''''   ''''''|+}}}}}}}}}|~||'                 
                   -||||||||||/|-                         ;~+/}}}}}|||||-'                 
                 ';~~}}}||||||=~;           }/}'      |//'';=/}}}}||||||- '                
                  ~||}}}||||||=-'         ;++==+~   ;++==+~;=/}}||||||||||'                
                ;||||||}}}||||=-'        '-+===+~' '-+===+~;=/}|||||||||||~;'              
                ;~||||||}}}|||=-'         ''}//''   ''}//'';=}||||||||||||~'   ''          
               -;|||||||}}}|}}}-'         ''''         '''';=}|||||||||||~  ; ;';;         
              --||||||||}}}}+/;''         ';;;   '~~-  ';;;;=}||||||||||||-''              
              -|||||||||}}}}+/'';|''      ''''   '~~-  '''''=+}||||||||||||;' ''           
              ';-|||||||}}}}+/'''-}~'                      '--~/||||||||||- -~; ;          
              ;~'||||||}}}}}+/''  ;~//~''''''            '''''';}/|||||||||--;             
                ;||||||}}}}}+/''   '''|+++++;''''' ''''''/++++} }/||||||||~''  ''          
                ~||||||}}}}}/}''       '''' }///++ }+////'''''' '-=||||||~ '~  '     '     
                '~||||}}}}}=|;''          '-----|} ~}----'       -=|||||||; ~-             
               '-||||}}}}}}=~;            ;}+/}}-   ;}++}'       -=|||||||~;~~;'  ''       
              '~||||}}}}}}}=~'              /}'''   ''/}''       -=|||||||~-;' '           
              -||||}}}}}}}}=~'            ;}~-'     ''-|}''      -=|||||||' '              
              ~||}}}}}}}}/+~;'           |}-''        ''-}~'    '~=|||||}};'--;            
              '|}}}}}}}}}/+;'        '';+~;''          '';|/''''}/|}}}}}}};   ~-           
             ~''}}}}}}}}}/+''       '/+/''                ';++++||}}}}}}}}; ;' '           
             ;~}}}}}}}}}}/+''                              ''}+}}}}}}}}}}}  ''             
               -}}}}}}}}//}'                               ''}+}}}}}}}}}~                  
               -}}}}}}}}=|;''  ''                         ''|/+}}}}}}}}}|''-               
               |||}}}}}}=|';'''''''                    '''';=+/}}}}}}}}|-                  
               ~}}}}}}}}=|''''''''''''''''       '''  ''''';=/}}}}}}}}|; ;-;;';'           
               |}}}}}}}}=|'''''''''''''''''     ''''''''''~//}}}}}}}}||;   ''              
               ;;}}}}}}}=|''''''''''''''''''''''''''''''';}+}}}}}}}}}~  ';'                
                 '|}}}}}+|;''''''''''''''''''''''''''''''+/}}}}}}}}|~  ;--|'               
              '' -||||||}/+~;''''''''''''---''''''''''';~+/}}}}}}}|-'     ''               
                 '~;~|||||}+}~'''''';~~||}//~~~'''''''~}+}}}}}}}}}- '  '' '                
                  ;'-||||||}//}||||}}////|||}//||}}}}}//}}}}}}}}}|' '   ''                 
                     -|||||||}///////}}}}}}}}}}///////}}}}}}}}}~'                          
                      -||||||||}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}|; ;'''                      
                        ;||||||}}}}}}}}}}}}}}}}}}}}}}}}}}}}}|;'  '                         
                     ;+//}/+++++++++++//====/}}}}}}}}}}}}}|;                               
                     '}}}|||+==/|}}/+=}|}===/}}}}}}}}}~---'                                
                            }==~   ';   '}==||~----;;                                      
                            }==~         |==|;|~~~-    '    ;~~~~;                         
                            }==~         |==+=+/===='     ~==/}/===;                       
                            }==~         |==/    /==|    }==;   '==+                       
                            }==~         |==-    -==|   ;==}     +==                       
                            }==~         |==-    ;==|   |===++++===+                       
                            }==~         |==-    ;==|   |==}                               
                            }==~         |==-    ;==}   -==+                               
                            /==~         |==-    ;==}    +==/'    ;~                       
                          }/===+/|     '/===+/   ;===/    |+=======/                       
                                                             ';;''                         
                                                                                           
               ~~~~~~~~--;                                            /===}                
               ~}===+/+====+~                                          ~==/                
                -==+     ~===/                                         '==/                
                -==+      '===|       ;---;       ';;;;;'          ;----==/                
                ;==+       }===     |==+/===|   ;===++===+-     '/==//+===/                
                ;==+       -===   '+=/    /==-   |};   ~===    ;==}    ;==/                
                ;==+       -===   }==;    -==|          +==    +==     '==/                
                ;==+       -===   ===/////===~     ;-~~~+==   '==+     '==/                
                -==+       |==|   ===-;;;;;;'   '/=+}|||+==   ;==+     '==/                
                -==+      '==='   ===-          /==     /==   '==='    '==/                
                -===;   '~==+'    ~===;     ;'  ===;   '==='   +==/    |==+                
               }/=========/-       ~+===+++==~  ~===+/++}==+'  '+===//=/+==}               
               ;;;;;;;;'             ';---;'      ---;'  ;;'     '---;   -;                
                                                                                           
             ;~~~~~-'                               -|~                                    
          -/==+//+==='                    -        ~===-                                   
         /==|      ;-                    -=+        -~;                                    
        |==|             ''      ''      /==        ''          ';;'         ';;;'         
       '==='           ~===}   -===/   |========| -+==='     -/======~    -/=======;       
       -===             ;==/    '==/     ===        +=='    }==;   }==~  -==~   '-|        
       ~==+             '==/     ==+     ===        /=='   ~==~    '==/  ~==}              
       |===             '==/     ==+     ===        /=='   +==}|||}/==}   }===/|-          
       ~==='            '==/     ==+     ===        /=='   +==|------;      -}+===}        
       '===|             ==+     ==+     ===        /=='   /==~                '}==}       
        |===|      '-    ==='   -==+     +=='       /=='   -===;     ''   '     '==}       
         ~+===+///===;   |===}}/=+==}    |==+}}+  ;|===}~   ~===+}}/+=}  |==/}}}==/        
           '-~|||~-;      ;~|~-'  ~-'     '-~~-;  '-----;     ;-~~~~-'    -~|||~-'         
                                                                               ASCII art by BufoBats            
                                                                                                                                                                                                                                                                       
 */
contract TheDeadCuties is ERC721Enumerable, Ownable {
    /*  
    ================================================================
                            State 
    ================================================================ 
    */

    string public baseURI;

    uint256 public mintPrice = 0.03 ether;

    uint256 public reRollPrice = 0.015 ether;

    uint256 public maxSupply = 10000;

    uint256 public timeLimit = 10 minutes;

    uint256 internal _totalSupply;

    address public accessToken;

    address public team;

    mapping(address => uint256) _timeAccessTokenDeposited;

    constructor() ERC721("TheDeadCuties", "DEAD") {}

    /*  
    ================================================================
                        Public Functions
    ================================================================ 
    */

    function depositAccessToken() external setTimeOfAccessTokenDeposit {
        takeOneAccessTokenFromSender();
        mintNFT();
    }

    function mint(uint256 amount) external payable senderHasEnoughTimeLeft hasPaidCorrectAmountForMint(amount) {
        for (uint256 i = 0; i < amount; i++) {
            mintNFT();
        }
    }

    function reRoll(uint256 tokenId) external payable senderOwnsNFT(tokenId) senderHasEnoughTimeLeft hasPaidCorrectAmountForReRoll {
        burnNFT(tokenId);
        mintNFT();
    }

    /*  
    ================================================================
                        Public returns
    ================================================================ 
    */

    function timeAccessTokenDeposited(address account) public view returns (uint256) {
        return _timeAccessTokenDeposited[account];
    }

    function getMintPrice() public view returns (uint256) {
        return mintPrice;
    }

    function getReRollPrice() public view returns (uint256) {
        return reRollPrice;
    }

    function walletOfOwner(address _wallet) public view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_wallet);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_wallet, i);
        }
        return tokensId;
    }

    /*  
    ================================================================
                            Modifers 
    ================================================================ 
    */

    modifier senderHasEnoughTimeLeft() {
        if (timeLimit > 0) {
            uint256 expireTime = _timeAccessTokenDeposited[msg.sender] + timeLimit;
            require(expireTime > block.timestamp, "TheDeadCuties: Out of time");
        }
        _;
    }

    modifier hasPaidCorrectAmountForMint(uint256 amount) {
        uint256 requiredPayment = calculatePriceBasedOn3For2Offer(amount);
        require(requiredPayment == msg.value, "TheDeadCuties: Payment incorrect");
        payable(team).transfer(requiredPayment);
        _;
    }

    modifier hasPaidCorrectAmountForReRoll() {
        require(reRollPrice == msg.value, "TheDeadCuties: Payment incorrect");
        payable(team).transfer(reRollPrice);
        _;
    }

    modifier incrementTotalSupply() {
        _totalSupply++;
        require(_totalSupply <= maxSupply, "TheDeadCuties: Max supply reached");
        _;
    }

    modifier setTimeOfAccessTokenDeposit() {
        _timeAccessTokenDeposited[msg.sender] = block.timestamp;
        _;
    }

    modifier senderOwnsNFT(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "TheDeadCuties: This isn't the senders token");
        _;
    }

    /*  
    ================================================================
                            Internal Functions 
    ================================================================ 
    */

    function burnNFT(uint256 tokenId) internal {
        _burn(tokenId);
        require(!_exists(tokenId), "TheDeadCuties: Token can't be burnt");
    }

    function mintNFT() internal incrementTotalSupply {
        _mint(msg.sender, _totalSupply);
    }

    function takeOneAccessTokenFromSender() internal {
        bool hasTransfered = IERC20(accessToken).transferFrom(msg.sender, address(this), 1);
        require(hasTransfered, "TheDeadCuties: Access token not transfered");
    }

    function calculatePriceBasedOn3For2Offer(uint256 amount) internal view returns (uint256) {
        uint256 noOffer = amount % 3;
        uint256 offer = amount / 3;
        uint256 price = ((offer * 2) * mintPrice) + (noOffer * mintPrice);
        return price;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /*  
    ================================================================
                            Owner Functions 
    ================================================================ 
    */

    function setAccessToken(address _accessToken) external onlyOwner {
        accessToken = _accessToken;
    }

    function setMintPrice(uint256 _mintPrice) external onlyOwner {
        mintPrice = _mintPrice;
    }

    function setReRollPrice(uint256 _reRollPrice) external onlyOwner {
        reRollPrice = _reRollPrice;
    }

    function withdrawEther() external onlyOwner {
        payable(team).transfer(address(this).balance);
    }

    function setTeam(address _team) external onlyOwner {
        team = _team;
    }

    function setBaseURI(string memory baseURI_) external onlyOwner {
        baseURI = baseURI_;
    }

    function setTimeLimit(uint256 _timeLimit) external onlyOwner {
        timeLimit = _timeLimit;
    }

    function removeNeedForAccessToken() external onlyOwner {
        timeLimit = 0;
    }
}

