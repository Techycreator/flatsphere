-- Voice notes are recorded as compressed Opus/AAC in browsers, so allow those types as well as WAV.
update storage.buckets
set allowed_mime_types = array['image/jpeg','audio/wav','audio/webm','audio/mp4']
where id = 'complaint-media';
