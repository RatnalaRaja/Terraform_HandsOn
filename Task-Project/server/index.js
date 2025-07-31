require('dotenv').config();
const express = require('express');
const {
  S3Client,
  GetObjectCommand,
  PutObjectCommand,
  ListObjectsV2Command,
} = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const cors = require('cors');
const path = require('path');

const app = express();
const port = process.env.PORT || 3001;

const s3Client = new S3Client({ region: process.env.AWS_REGION });
const BUCKET_NAME = process.env.S3_BUCKET_NAME;

app.use(cors());
app.use(express.json());

app.use(express.static(path.join(__dirname, '..', 'client', 'build')));

// ✅ Presigned PUT URL for upload
app.get('/api/generate-upload-url', async (req, res) => {
  const { fileName, fileType } = req.query;
  if (!fileName || !fileType) {
    return res.status(400).send('fileName and fileType query parameters are required.');
  }

  const key = `uploads/${Date.now()}_${fileName}`;
  const command = new PutObjectCommand({
    Bucket: BUCKET_NAME,
    Key: key,
    ContentType: fileType,
  });

  try {
    const signedUrl = await getSignedUrl(s3Client, command, { expiresIn: 300 }); // 5 min
    res.json({ uploadUrl: signedUrl, key });
  } catch (error) {
    console.error('Error generating pre-signed URL', error);
    res.status(500).send('Could not generate upload URL.');
  }
});

// ✅ Presigned GET URL for a single image
app.get('/api/generate-view-url', async (req, res) => {
  const { key } = req.query;
  if (!key) return res.status(400).send('Missing key');

  try {
    const command = new GetObjectCommand({ Bucket: BUCKET_NAME, Key: key });
    const signedUrl = await getSignedUrl(s3Client, command, { expiresIn: 600 }); // 10 min
    res.json({ viewUrl: signedUrl });
  } catch (error) {
    console.error('Error generating view URL', error);
    res.status(500).send('Could not generate view URL.');
  }
});

// ✅ List all uploaded image URLs
app.get('/api/images', async (req, res) => {
  const command = new ListObjectsV2Command({
    Bucket: BUCKET_NAME,
    Prefix: 'uploads/',
  });

  try {
    const { Contents = [] } = await s3Client.send(command);
    const imageKeys = Contents.map(item => item.Key);

    const imageUrls = await Promise.all(
      imageKeys.map(async (key) => {
        const getCommand = new GetObjectCommand({ Bucket: BUCKET_NAME, Key: key });
        return getSignedUrl(s3Client, getCommand, { expiresIn: 3600 }); // 1 hour
      })
    );

    res.json(imageUrls.reverse());
  } catch (error) {
    console.error('Error listing images', error);
    res.status(500).send('Could not list images.');
  }
});

// 🔁 Serve React frontend for unmatched routes
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'client', 'build', 'index.html'));
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
  console.log(`S3 Bucket: ${BUCKET_NAME}`);
});
