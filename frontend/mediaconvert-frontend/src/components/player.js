"use client"
import ReactPlayer from 'react-player'

export default function MediaPlayer() {
  return (
    <div className="mx-auto w-screen h-screen">
      <ReactPlayer 
       width={"100%"}
       height={"90%"}
       playing={true}
       url='https://giistyxelor.s3.amazonaws.com/giists/video/video0cP3w019TiZYYcUy22WY.mp4'
       controls={true} />
    </div>
  )
}