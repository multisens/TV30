
function navigate(key) {

    let moveup = $('.focused').attr('moveup');
    let movedown = $('.focused').attr('movedown');
    let moveleft = $('.focused').attr('moveleft');
    let moveright = $('.focused').attr('moveright');
    let select = $('.focused').attr('select');
    let param = $('.focused').attr('selectParam');
    
    switch(key) {
        case 'ArrowUp':
            if (typeof moveup !== 'undefined' && $(`#${moveup}`).length > 0) {
                $('.focused').removeClass('focused');
                $(`#${moveup}`).addClass('focused');
            }
            break;
        case 'ArrowDown':
            if (typeof movedown !== 'undefined' && $(`#${movedown}`).length > 0) {
                $('.focused').removeClass('focused');
                $(`#${movedown}`).addClass('focused');
            }
            break;
        case 'ArrowLeft':
            if (typeof moveleft !== 'undefined' && $(`#${moveleft}`).length > 0) {
                $('.focused').removeClass('focused');
                $(`#${moveleft}`).addClass('focused');
            }
            break;
        case 'ArrowRight':
            if (typeof moveright !== 'undefined' && $(`#${moveright}`).length > 0) {
                $('.focused').removeClass('focused');
                $(`#${moveright}`).addClass('focused');
            }
            break;
        case 'Enter':
            if (typeof select !== 'undefined') {
                if (typeof param !== 'undefined') {
                    window[select](param);
                }
                else {
                    window[select]();
                }
            }
            break;
        default:
            return; // Exit if other key pressed
    }
}