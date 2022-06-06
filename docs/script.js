
var nuclick = 2;
navbtn.onclick =()=>{
    nuclick++;
    navcon.style.height = nuclick%2 == 1 ? "120px" : "0px";
    //console.log(nuclick%2);
}
