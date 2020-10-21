pragma solidity ^0.5.0;

import './Storage.sol';

contract MultiSignWalletCon is Storage {
    
     modifier onlyOwner() {
        require (msg.sender == owner);
        _;
    }
    
  
    constructor() public {
        
    }
    
     uint newBal;//test
     uint tobetransferred;
     uint tobeDeposited;
     
      //ERC20 events
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
    event Transfer(address indexed from, address indexed to, uint tokens);
    
     //other events
    event DepositToken(address _addr, uint tokensDeposited, string depositMsg);
    event RequestTokenWithdraw(address _addr, uint tokensToBeWithdrawn);
    event ConfirmWithdrawal(address _addr, uint tokensConfirmedToWithdraw);
    event RejectWithdrawal(address _addr,string msg);
    event TransferAmount(address, uint tokensTransferred, string msg);
    
    using SafeMath for uint256;
     
    /*
    depositWEI() will be called by the used to deposit the tokens.
    */
    function depositWEI()  
        payable public
    {
        
        string memory depositMsg= " ";
        newBal = address(this).balance ;
        
        uint newVal = msg.value + address(this).balance;
        
        if(newBal < maxWEI) {
            
            if(balances[msg.sender] == 0)  
                balances[msg.sender] = msg.value; 
            else
                balances[msg.sender] = balances[msg.sender]  + msg.value;    
                
            depositMsg = "Tokens have been deposited successfully";
                
        } else if( newBal == maxWEI) { 
            tobetransferred =  newBal - maxWEI;
            tobeDeposited = msg.value - (newBal - maxWEI);
            msg.sender.transfer(tobetransferred);
            if(balances[msg.sender] == 0)  
                balances[msg.sender] = tobeDeposited; 
            else
               balances[msg.sender] = balances[msg.sender] + tobeDeposited ;  
             
             depositMsg = "Max number of tokens have been reached. Token deposit has been rolled back.";
            
        } else {
            tobetransferred =  newBal - maxWEI;
            tobeDeposited = msg.value - (newBal - maxWEI);
            msg.sender.transfer(tobetransferred);
            if(balances[msg.sender] == 0)  
                balances[msg.sender] = tobeDeposited; 
            else
                balances[msg.sender] = balances[msg.sender] + tobeDeposited ; 
                
            depositMsg = "New token count has exceeded max count set. But partial amount will be deposited and remaining will be sent back to the account.";
        }
        
        emit DepositToken(msg.sender, msg.value, depositMsg);
    }
    
    
    /*
    requestForWithdrawal  will be called by the used to request for the tokens withdrawal. if the current tokens
    count is less then 32 ,then amount will be immediately transferred to the user account, else the wiuthdrawal request will be
    generated and would require 51% approval to reach consensus , to be eligible or transfer.
    */
    function requestForWithdrawal(uint value)
        public 
        returns (string memory)
    {
        string memory message= "" ;
        
       uint valInWEI = value * 1000000000000000000 ;
       if(address(this).balance < maxWEI) {
                require(balances[msg.sender] <= valInWEI); 
                balances[msg.sender] = balances[msg.sender] - valInWEI ;  
                msg.sender.transfer(valInWEI);
                //emit InstantTransferDone(value, data, _addr,"Tokens transfer done");
                message= "Tokens transfer done" ;
       } else {
           //code to submit the request for the approval.
           submitWithdrawalRequest(valInWEI);
           message= "Wthdrawal request generated.";
       }
       
       return message;
    }
    
    
    function submitWithdrawalRequest(uint value)
        public
        returns (uint transactionId)
    {
        transactionId = createWithdrawalRequest(msg.sender, value,"Withdrawal Request");
        //emit submitTrnx(destination,value,data,"Transaction submitted");
        return transactionId;
    }
    
     function createWithdrawalRequest(address destination, uint value, string memory transType)
        public
        returns (uint transactionId)
    {
        transactionId = transactionCount;
        
        //adding to the newtrxids array
        newtrxids.push(transactionId);
        
        //adding to the transactions mapping
        transactions[transactionId] = Transaction({
            destination: destination, //address which deposited the ethers/wei
            value: value,
            tranType: 'Withdrawal Request',
            executed: false,
            confirmCount: 0,
            rejectCount: 0,
            currentState: "New",
            creationDate: now,
            transferDate: 0
        });
       
        uint curTnxid = transactionCount;
        transactionCount += 1;
        return curTnxid;
    }
    
    
     /*
    confirmTransaction  will be called by the used to approve the transaction, identified by the transaction id.
    */
    function confirmTransaction(uint txid) 
        public
        returns(string memory)
    {
        require(hasConfirmed[msg.sender][txid] == false, "You have already confirmed this transaction");
       
       //transaction confirmation count
        transactions[txid].confirmCount =  transactions[txid].confirmCount + 1;
        
        // converting from payable to non payable address.
        address addr = address(msg.sender); 
        
        //storing addresses of users whoever has confirmed the transaction.
        confirmedTxToAddrMapping[txid].push(addr);
        
        hasConfirmed[msg.sender][txid] = true;
        
    }
    
     /*
    rejectTransaction  will be called by the used to approve the transaction, identified by the transaction id.
    */
     function rejectTransaction(uint txid) 
        public
        returns(string memory)
    {
        
        require(hasConfirmed[msg.sender][txid] == false, "You have already rejected this transaction");
        
        //transaction rejection count
        transactions[txid].rejectCount =  transactions[txid].rejectCount + 1;
        
        // converting from payable to non payable address.
        address addr = address(msg.sender);
        
        //adding addr that rejected the transaction.
        rejectedTxToAddrMapping[txid].push(msg.sender);
        
        hasConfirmed[msg.sender][txid] = true;
   
        
    }
    
  
    function isReadyForTransfer(uint txid) 
        public
        returns(bool)
    {
        //check for 51% approval.
        uint confirmations = transactions[txid].confirmCount;
        uint rejections = transactions[txid].rejectCount;
        
        uint confirmPercent= (confirmations * 51) / 100 ;
        
        if(confirmPercent > rejections) {
            
            transactions[txid].currentState = "Ready for transfer"; 
            return true;
        }
        
        return false;
    }
    
    /*
    TransferTokens  will be called by the user, once its transaction has achived minimum Consensus of 51% approval.
    */
    function transferTokens(uint txId) 
        public
        returns(bool)
    {
        uint confirmations = 53;
        uint rejections = 21 ;
        
        uint confirmPercent= (confirmations * 51) / 100 ;
        require(confirmPercent > rejections, "Consensus(51% approval) has not yet achieved");
        
        msg.sender.transfer(transactions[txId].value);
        transactions[txId].currentState = "Transfer done";
        
        uint updatedDeposit =  tokensDeposited[msg.sender] - transactions[txId].value;
        balances[msg.sender] = updatedDeposit;  

         
    }
    
    function checkTotalTokenDepositedByUser()  
        public view
        returns(uint256)
    {

       return balances[msg.sender];
    }
    
    
    function checkMsgSenderBal()  
        public view
        returns(uint256)
    {

       return msg.sender.balance;
    }
    
    function checkContractBal()  
        public view
        returns(uint256)
    {

       return address(this).balance;
    }

     function checknewBal()  
        public view
        returns(uint256)
    {

       return newBal;
    }
    
    function checktobetransferred()  
        public view
        returns(uint)
    {

       return tobetransferred;
    }
    
    function checktobeDeposited()  
        public view
        returns(uint)
    {

       return tobetransferred;
    }
    
    
    function checktransactionCount()
        public view
        returns(uint)
    {
        return transactionCount;
    }
    
    function checktransactionTokens(uint txId)
        public view
        returns(uint)
    {
        return transactions[txId].value;
    }
    
     function checktransactionTokensByAddr()
        public view
        returns(uint)
    {
        return balances[msg.sender];
    }
    
  
    //ERC20 METHODS
    
  
   function totalSupply() public view returns (uint256) {
	    return totalSupply_;
    }
    
    function balanceOf(address tokenOwner) public view returns (uint) {
        return balances[tokenOwner];
    }
    
    function transfer(address receiver, uint numTokens) public returns (bool) {
        require(numTokens <= balances[msg.sender]);
        balances[msg.sender] = balances[msg.sender].sub(numTokens);
        balances[receiver] = balances[receiver].add(numTokens);
        emit Transfer(msg.sender, receiver, numTokens);
        return true;
    }
    
    function approve(address delegate, uint numTokens) public returns (bool) {
        allowed[msg.sender][delegate] = numTokens;
        emit Approval(msg.sender, delegate, numTokens);
        return true;
    }
    
    function allowance(address owner, address delegate) public view returns (uint) {
        return allowed[owner][delegate];
    }
    
    function transferFrom(address owner, address buyer, uint numTokens) public onlyOwner returns (bool) {
        
        require(numTokens <= balances[owner]);    
        require(numTokens <= allowed[owner][msg.sender]);
    
        balances[owner] = balances[owner].sub(numTokens);
        allowed[owner][msg.sender] = allowed[owner][msg.sender].sub(numTokens);
        balances[buyer] = balances[buyer].add(numTokens);
        emit Transfer(owner, buyer, numTokens);
        return true;
    }
    
}

library SafeMath { 
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
      assert(b <= a);
      return a - b;
    }
    
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
      uint256 c = a + b;
      assert(c >= a);
      return c;
    }
}
