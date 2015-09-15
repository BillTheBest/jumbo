var PREFIX = $('html').data('prefix');
var RESOLVE = function(me, data, done) {
	if ('function' === typeof data) {
		done = data;
		data = null;
	};
		
	me.prop('disabled', true);
	
	$.ajax({
		type: 'POST',
		url: PREFIX +'/api/resolve/'+ me.data('type') +'/'+ me.data('type-id') +'/'+ me.data('id'),
		data: JSON.stringify(data ? data : {}),
		dataType: 'json',
		contentType: 'application/json; charset=utf-8',
		cache: false,
		success: function(data) {
			me.prop('disabled', false);
			
			switch (data.status) {
				case 'ok':
					me.closest('tr').find('pre').remove();
					me.closest('tr').find('.glyphicon')
						.removeClass('glyphicon-question-sign')
						.removeClass('glyphicon-remove-sign')
						.removeClass('text-danger')
						.removeClass('text-warning')
						.addClass('text-success')
						.addClass('glyphicon-ok-sign');

					me.remove();
					
					done(null);
					break;
				
				case 'error':
					done(data);
					break;
			}
		}
	});
}

$(document).on('click', '.jumbo-resolve-all', function(event) {
	var me = $(this).prop('disabled', true);

	async.eachSeries($('.jumbo-resolve').toArray(), function(elm, next) {
		RESOLVE($(elm), next);
	}, function(err) {
		if (err) return alert(err.message);
	});
});

$(document).on('click', '.jumbo-resolve', function(event) {
	RESOLVE($(this), function(err) {
		if (err) return alert(err.message);
	});
});

$(document).on('click', '.jumbo-sync', function(event) {
	var me = $(this).prop('disabled', true);
	
	$.ajax({
		type: 'POST',
		url: '/api/sync',
		dataType: 'json',
		success: function(data) {
			me.prop('disabled', false);
			
			switch (data.status) {
				case 'ok':
					location.reload();
					break;
				
				case 'error':
					alert(data.stack);
					break;
			}
		}
	});
});

$(document).on('click', 'h2', function(event) {
	$(this).next('table').find('.collapse').removeClass('collapse');
});